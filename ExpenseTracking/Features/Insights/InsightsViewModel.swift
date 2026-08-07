import Foundation
import Observation
import CashFlowKit
import CashFlowData

struct InsightsSliceRow: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let total: Decimal
    let amountText: String
    let share: Double

    init(slice: SpendingSlice, expenseTotal: Decimal) {
        self.id = slice.id
        self.name = slice.name
        self.total = slice.total
        self.amountText = CurrencyFormatting.usd(slice.total)
        if expenseTotal > 0 {
            self.share = NSDecimalNumber(decimal: slice.total / expenseTotal).doubleValue
        } else {
            self.share = 0
        }
    }
}

@MainActor
@Observable
final class InsightsViewModel {
    private let transactionRepository: any TransactionRepository
    private let tagRepository: any TagRepository
    private let syncServing: any SyncServing
    private let calculateSpendingBreakdown: CalculateSpendingBreakdownUseCase

    var selectedOption: HomeRangeOption = .month
    var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    var customEnd: Date = .now
    var showCustomRange = false
    var isLoading = true
    var isRefreshing = false
    var bannerMessage: String?
    var syncProgress: SyncProgress?
    var earliestPostedDate: Date?
    var availableRangeOptions: [HomeRangeOption] = HomeRangeOption.pickerOptions(earliestPosted: nil)

    var categoryRows: [InsightsSliceRow] = []
    var tagRows: [InsightsSliceRow] = []
    var expenseTotalText = CurrencyFormatting.usd(0)
    var hasExpenseData = false

    var tags: [CashFlowKit.Tag] = []
    var showManageTags = false
    var newTagName = ""
    var renamingTagID: TagID?
    var renameDraft = ""
    var isSavingTag = false
    /// Shown inside Manage Tags (banner on Insights is covered by the sheet).
    var tagEditorError: String?

    private var reloadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    private var syncProgressTask: Task<Void, Never>?

    init(
        transactionRepository: any TransactionRepository,
        tagRepository: any TagRepository,
        syncServing: any SyncServing,
        calculateSpendingBreakdown: CalculateSpendingBreakdownUseCase
    ) {
        self.transactionRepository = transactionRepository
        self.tagRepository = tagRepository
        self.syncServing = syncServing
        self.calculateSpendingBreakdown = calculateSpendingBreakdown
    }

    var selectedRange: CashFlowDateRange {
        selectedOption.dateRange(customStart: customStart, customEnd: customEnd)
    }

    var categorySectionTitle: String { "By category" }

    var tagSectionTitle: String { "By tag" }

    func onAppear() async {
        startObservingSyncProgress()
        await reload(preferLoadingIndicator: !hasExpenseData && categoryRows.isEmpty)
    }

    private func startObservingSyncProgress() {
        guard syncProgressTask == nil else { return }
        syncProgressTask = Task { [syncServing] in
            for await progress in syncServing.syncProgressUpdates() {
                guard !Task.isCancelled else { break }
                syncProgress = progress
            }
        }
    }

    /// Updates the segmented control synchronously, then reloads (cancelling any in-flight range load).
    func selectOption(_ option: HomeRangeOption) {
        guard availableRangeOptions.contains(option) else { return }
        if option == .custom {
            showCustomRange = true
            return
        }
        selectedOption = option
        scheduleReload(preferLoadingIndicator: false)
    }

    func applyCustomRange() {
        selectedOption = .custom
        showCustomRange = false
        scheduleReload(preferLoadingIndicator: false)
    }

    private func scheduleReload(preferLoadingIndicator: Bool) {
        reloadTask?.cancel()
        reloadTask = Task { await reload(preferLoadingIndicator: preferLoadingIndicator) }
    }

    func reload(preferLoadingIndicator: Bool = true) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        // Capture range up front so a later selection change cannot alter this load's query.
        let range = selectedRange
        if preferLoadingIndicator {
            isLoading = true
        }
        defer {
            if generation == reloadGeneration {
                isLoading = false
            }
        }

        do {
            earliestPostedDate = try await transactionRepository.earliestPostedDate()
            guard generation == reloadGeneration, !Task.isCancelled else { return }

            availableRangeOptions = HomeRangeOption.pickerOptions(earliestPosted: earliestPostedDate)
            if !availableRangeOptions.contains(selectedOption) {
                selectedOption = .month
            }

            async let transactionsTask = transactionRepository.fetchPosted(
                in: range,
                now: .now
            )
            async let tagsTask = tagRepository.fetchAll()
            let transactions = try await transactionsTask
            let fetchedTags = try await tagsTask
            guard generation == reloadGeneration, !Task.isCancelled else { return }

            tags = fetchedTags
            cachedTransactions = transactions
            applyBreakdown(transactions: transactions, tags: fetchedTags, range: range)
            bannerMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == reloadGeneration else { return }
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't load spending."
            )
        }
    }

    private func applyBreakdown(
        transactions: [Transaction],
        tags: [CashFlowKit.Tag],
        range: CashFlowDateRange
    ) {
        let result = calculateSpendingBreakdown.execute(
            transactions: transactions,
            tags: tags,
            range: range,
            scope: .all
        )
        categoryRows = result.byCategory.map {
            InsightsSliceRow(slice: $0, expenseTotal: result.expenseTotal)
        }
        tagRows = result.byTag.map {
            InsightsSliceRow(slice: $0, expenseTotal: result.expenseTotal)
        }
        expenseTotalText = CurrencyFormatting.usd(result.expenseTotal)
        hasExpenseData = result.expenseTotal > 0
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            _ = try await syncServing.syncNow()
            bannerMessage = nil
        } catch {
            let detail = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't refresh."
            )
            bannerMessage = "\(detail) Showing last saved data."
        }
        await reload(preferLoadingIndicator: false)
    }

    func createTag() async {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingTag = true
        defer { isSavingTag = false }
        do {
            let created = try await tagRepository.create(name: name)
            newTagName = ""
            tagEditorError = nil
            // Prefer store read-back; fall back to local insert if fetch races.
            if let latest = try? await tagRepository.fetchAll(), !latest.isEmpty {
                tags = latest
            } else {
                upsertLocalTag(created)
            }
            // Refresh charts without blocking tag list on spending fetch errors.
            await reloadBreakdownPreservingTags()
        } catch {
            tagEditorError = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't create tag."
            )
        }
    }

    func beginRename(_ tag: CashFlowKit.Tag) {
        renamingTagID = tag.id
        renameDraft = tag.name
        tagEditorError = nil
    }

    func commitRename() async {
        guard let id = renamingTagID else { return }
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingTag = true
        defer { isSavingTag = false }
        do {
            try await tagRepository.rename(id: id, name: name)
            renamingTagID = nil
            renameDraft = ""
            tagEditorError = nil
            await reloadTagsAndBreakdown()
        } catch {
            tagEditorError = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't rename tag."
            )
        }
    }

    func deleteTag(_ tag: CashFlowKit.Tag) async {
        isSavingTag = true
        defer { isSavingTag = false }
        do {
            try await tagRepository.delete(id: tag.id)
            tags.removeAll { $0.id == tag.id }
            tagEditorError = nil
            await reload(preferLoadingIndicator: false)
        } catch {
            tagEditorError = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't delete tag."
            )
        }
    }

    func prepareManageTags() {
        tagEditorError = nil
        newTagName = ""
        renamingTagID = nil
        renameDraft = ""
    }

    private func reloadTagsAndBreakdown() async {
        do {
            tags = try await tagRepository.fetchAll()
        } catch {
            // Keep existing list on fetch failure.
        }
        await reloadBreakdownPreservingTags()
    }

    /// Reloads spending charts but does not clear `tags` if the spending fetch fails.
    private func reloadBreakdownPreservingTags() async {
        let preservedTags = tags
        await reload(preferLoadingIndicator: false)
        if tags.isEmpty && !preservedTags.isEmpty {
            tags = preservedTags
        }
    }

    private func upsertLocalTag(_ tag: CashFlowKit.Tag) {
        if let index = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[index] = tag
        } else {
            tags.append(tag)
        }
        tags.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
