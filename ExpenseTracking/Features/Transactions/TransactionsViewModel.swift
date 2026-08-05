import Foundation
import Observation
import CashFlowKit
import CashFlowData

struct ActiveFilterChip: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case account
        case date
        case category
        case tag
    }

    var id: Kind { kind }
    let kind: Kind
    let label: String
}

@MainActor
@Observable
final class TransactionsViewModel {
    private let transactionRepository: any TransactionRepository
    private let accountRepository: any AccountRepository
    private let tagRepository: any TagRepository
    private let syncServing: any SyncServing
    private let ruleRepository: any CategorizationRuleRepository
    private let ruleApplying: any CategorizationRuleApplying
    private let ruleDrafting: (any CategorizationRuleDrafting)?
    private let availabilityChecker: (any OnDeviceModelAvailabilityChecking)?

    var rows: [TransactionRowModel] = []
    var accounts: [Account] = []
    var tags: [CashFlowKit.Tag] = []
    var searchText = ""
    var filterAccountID: AccountID?
    var filterCategoryID: CategoryID?
    var filterTagID: TagID?
    var filterDateOption: TransactionDateFilterOption = .all
    var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    var customEnd: Date = .now
    var showFilters = false
    var showCustomRange = false
    var isLoadingPage = false
    var hasMore = true
    var bannerMessage: String?
    var syncProgress: SyncProgress?
    var selectedTransactionID: TransactionID?
    var editingDescription = ""
    var editingCategoryID: CategoryID = SystemCategory.other.id
    var editingCategoryLocked = false
    var editingTagIDs: Set<TagID> = []
    var editingAccountName = ""
    var editingLocation: String?
    var newTagName = ""
    var matchingRules: [CategorizationRule] = []
    var showRuleEditor = false
    var ruleEditor: CategorizationRuleEditorViewModel?
    var isSavingEdits = false

    private var cursor: TransactionCursor?
    private var loadTask: Task<Void, Never>?
    private var accountNames: [AccountID: String] = [:]
    private var tagNames: [TagID: String] = [:]
    private var matchingRulesTask: Task<Void, Never>?
    private var syncProgressTask: Task<Void, Never>?

    init(
        transactionRepository: any TransactionRepository,
        accountRepository: any AccountRepository,
        tagRepository: any TagRepository,
        syncServing: any SyncServing,
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        ruleDrafting: (any CategorizationRuleDrafting)? = nil,
        availabilityChecker: (any OnDeviceModelAvailabilityChecking)? = nil
    ) {
        self.transactionRepository = transactionRepository
        self.accountRepository = accountRepository
        self.tagRepository = tagRepository
        self.syncServing = syncServing
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.ruleDrafting = ruleDrafting
        self.availabilityChecker = availabilityChecker
    }

    var filter: TransactionFilter {
        TransactionFilter(
            accountID: filterAccountID,
            dateRange: filterDateOption.dateRange(
                customStart: customStart,
                customEnd: customEnd
            ),
            categoryID: filterCategoryID,
            tagID: filterTagID
        )
    }

    var hasActiveFilters: Bool {
        !activeFilterChips.isEmpty
    }

    /// Visible summary of non-default filters (account / date / category).
    var activeFilterChips: [ActiveFilterChip] {
        var chips: [ActiveFilterChip] = []
        if let filterAccountID {
            let name = accountNames[filterAccountID]
                ?? accounts.first(where: { $0.id == filterAccountID })?.name
                ?? "Account"
            chips.append(ActiveFilterChip(kind: .account, label: name))
        }
        if filterDateOption != .all {
            let label: String
            if filterDateOption == .custom {
                label = "\(DateFormatting.list(customStart)) – \(DateFormatting.list(customEnd))"
            } else {
                label = filterDateOption.title
            }
            chips.append(ActiveFilterChip(kind: .date, label: label))
        }
        if let filterCategoryID {
            chips.append(
                ActiveFilterChip(
                    kind: .category,
                    label: SystemCategory.category(for: filterCategoryID).name
                )
            )
        }
        if let filterTagID {
            chips.append(
                ActiveFilterChip(
                    kind: .tag,
                    label: tagNames[filterTagID]
                        ?? tags.first(where: { $0.id == filterTagID })?.name
                        ?? "Tag"
                )
            )
        }
        return chips
    }

    var displayedRows: [TransactionRowModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            row.title.localizedCaseInsensitiveContains(query)
                || row.location?.localizedCaseInsensitiveContains(query) == true
                || row.categoryText.localizedCaseInsensitiveContains(query)
                || row.tagText?.localizedCaseInsensitiveContains(query) == true
                || row.accountName.localizedCaseInsensitiveContains(query)
                || TransactionAmountSearch.matches(query, amountText: row.amountText)
        }
    }

    /// Pending section first (when present), then month sections newest → oldest.
    var sections: [TransactionMonthSection] {
        let visible = displayedRows
        let pendingRows = visible.filter(\.isPending)
        let postedRows = visible.filter { !$0.isPending }

        var result: [TransactionMonthSection] = []
        if !pendingRows.isEmpty {
            result.append(
                TransactionMonthSection(key: "pending", title: "Pending", rows: pendingRows)
            )
        }

        var orderedKeys: [String] = []
        var buckets: [String: [TransactionRowModel]] = [:]
        var titles: [String: String] = [:]

        for row in postedRows {
            if buckets[row.sectionKey] == nil {
                orderedKeys.append(row.sectionKey)
                titles[row.sectionKey] = row.sectionTitle
                buckets[row.sectionKey] = []
            }
            buckets[row.sectionKey]?.append(row)
        }

        result.append(contentsOf: orderedKeys.compactMap { key in
            guard let rows = buckets[key], let title = titles[key] else { return nil }
            return TransactionMonthSection(key: key, title: title, rows: rows)
        })
        return result
    }

    private var hasLoadedOnce = false

    func onAppear() async {
        startObservingSyncProgress()
        await refreshAccounts()
        await refreshTags()
        // Avoid resetting the list (and scroll position) every time the tab reappears.
        guard !hasLoadedOnce else { return }
        hasLoadedOnce = true
        await resetAndLoad()
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

    func applyFilters() async {
        showFilters = false
        await resetAndLoad()
    }

    /// Opens the list focused on one account (from Accounts tab).
    func focusAccount(_ accountID: AccountID) async {
        filterAccountID = accountID
        filterCategoryID = nil
        filterTagID = nil
        filterDateOption = .all
        await refreshAccounts()
        await refreshTags()
        hasLoadedOnce = true
        await resetAndLoad()
    }

    /// Opens the list from Insights with optional category and/or tag (AND) plus date range.
    func focusInsights(
        categoryID: CategoryID?,
        tagID: TagID?,
        dateOption: TransactionDateFilterOption,
        customStart: Date,
        customEnd: Date
    ) async {
        filterAccountID = nil
        filterCategoryID = categoryID
        filterTagID = tagID
        filterDateOption = dateOption
        self.customStart = customStart
        self.customEnd = customEnd
        await refreshAccounts()
        await refreshTags()
        hasLoadedOnce = true
        await resetAndLoad()
    }

    func clearFilter(_ kind: ActiveFilterChip.Kind) async {
        switch kind {
        case .account:
            filterAccountID = nil
        case .date:
            filterDateOption = .all
        case .category:
            filterCategoryID = nil
        case .tag:
            filterTagID = nil
        }
        await resetAndLoad()
    }

    func clearAllFilters() async {
        filterAccountID = nil
        filterCategoryID = nil
        filterTagID = nil
        filterDateOption = .all
        await resetAndLoad()
    }

    func resetAndLoad() async {
        hasLoadedOnce = true
        loadTask?.cancel()
        rows = []
        cursor = nil
        hasMore = true
        await loadNextPage()
    }

    func loadNextPageIfNeeded(currentRowID: TransactionID) async {
        guard hasMore, !isLoadingPage else { return }
        guard let index = rows.firstIndex(where: { $0.id == currentRowID }) else { return }
        if index >= rows.count - 10 {
            await loadNextPage()
        }
    }

    func loadNextPage() async {
        guard hasMore, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }

        do {
            let page = try await transactionRepository.fetchPage(
                filter: filter,
                cursor: cursor,
                limit: TransactionPageSize.default
            )
            let mapped = page.items.map { tx in
                TransactionRowModel(
                    transaction: tx,
                    accountName: accountNames[tx.accountID] ?? "Account",
                    tagNamesByID: tagNames
                )
            }
            rows.append(contentsOf: mapped)
            cursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't load transactions."
            )
        }
    }

    func refresh() async {
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
        await refreshAccounts()
        await refreshTags()
        await resetAndLoad()
    }

    func openEditor(for id: TransactionID) {
        selectedTransactionID = id
        newTagName = ""
        if let row = rows.first(where: { $0.id == id }) {
            applyEditorFields(from: row)
        }
        Task {
            // Load tags before matching rules so the Tags section is populated
            // when the medium detent sheet appears.
            await refreshTags()
            // Prefer store state over a possibly stale list row (e.g. after Assistant).
            await hydrateEditorFromStore(id: id)
            await refreshMatchingRules()
            await reapplyIfCategoryOutOfSync(for: id)
        }
    }

    /// If an unlocked row matches a categorize rule but still has another category,
    /// re-run rules so the editor reflects what the rule engine would apply.
    private func reapplyIfCategoryOutOfSync(for id: TransactionID) async {
        guard !editingCategoryLocked,
              let rule = matchingRules.first(where: \.appliesCategory),
              rule.categoryID != editingCategoryID
        else { return }
        do {
            _ = try await ruleApplying.reapplyAllRules()
            await hydrateEditorFromStore(id: id)
            await refreshMatchingRules()
        } catch {
            // Leave the editor on the hydrated snapshot; Save can still persist manual edits.
        }
    }

    private func applyEditorFields(from row: TransactionRowModel) {
        editingDescription = row.title
        editingCategoryID = row.categoryID
        editingCategoryLocked = row.categoryLocked
        editingTagIDs = Set(row.tagIDs)
        editingAccountName = row.accountName
        editingLocation = row.location
    }

    private func hydrateEditorFromStore(id: TransactionID) async {
        do {
            let transactions = try await transactionRepository.fetchAllForCategorization()
            guard let transaction = transactions.first(where: { $0.id == id }) else { return }
            let row = TransactionRowModel(
                transaction: transaction,
                accountName: accountNames[transaction.accountID]
                    ?? accounts.first(where: { $0.id == transaction.accountID })?.name
                    ?? "Account",
                tagNamesByID: tagNames
            )
            applyEditorFields(from: row)
            if let index = rows.firstIndex(where: { $0.id == id }) {
                rows[index] = row
            }
        } catch {
            // Keep the list-row snapshot already applied in openEditor.
        }
    }

    /// Call when the Transactions tab becomes active so newly created Insights tags appear.
    func refreshTagsIfNeeded() async {
        await refreshTags()
    }

    func toggleEditingTag(_ tagID: TagID) {
        if editingTagIDs.contains(tagID) {
            editingTagIDs.remove(tagID)
        } else {
            editingTagIDs.insert(tagID)
        }
    }

    func createTagFromEditor() async {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let tag = try await tagRepository.create(name: name)
            newTagName = ""
            await refreshTags()
            // Ensure the new tag is visible even if fetch is briefly stale.
            if !tags.contains(where: { $0.id == tag.id }) {
                tags.append(tag)
                tags.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                tagNames[tag.id] = tag.name
            }
            editingTagIDs.insert(tag.id)
        } catch {
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't create tag."
            )
        }
    }

    func presentCreateRule() {
        ruleEditor = CategorizationRuleEditorViewModel(
            ruleRepository: ruleRepository,
            ruleApplying: ruleApplying,
            accountRepository: accountRepository,
            tagRepository: tagRepository,
            ruleDrafting: ruleDrafting,
            availabilityChecker: availabilityChecker,
            prefillTitle: editingDescription,
            prefillCategoryID: editingCategoryID
        )
        showRuleEditor = true
    }

    func presentEditRule(_ rule: CategorizationRule) {
        ruleEditor = CategorizationRuleEditorViewModel(
            ruleRepository: ruleRepository,
            ruleApplying: ruleApplying,
            accountRepository: accountRepository,
            tagRepository: tagRepository,
            ruleDrafting: ruleDrafting,
            availabilityChecker: availabilityChecker,
            existing: rule
        )
        showRuleEditor = true
    }

    func handleRuleEditorDismissed() async {
        let saved = ruleEditor?.didSave == true
        ruleEditor = nil
        guard saved else { return }
        let editingID = selectedTransactionID
        await resetAndLoad()
        if let editingID, let row = rows.first(where: { $0.id == editingID }) {
            // Rule re-apply may have renamed/categorized — keep the open editor in sync
            // so Save doesn’t write the pre-rule title back over the rename.
            editingDescription = row.title
            editingCategoryID = row.categoryID
            editingCategoryLocked = row.categoryLocked
            editingTagIDs = Set(row.tagIDs)
            editingAccountName = row.accountName
            editingLocation = row.location
        }
        await refreshMatchingRules()
    }

    func scheduleMatchingRulesRefresh() {
        matchingRulesTask?.cancel()
        matchingRulesTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await refreshMatchingRules()
        }
    }

    func refreshMatchingRules() async {
        guard let id = selectedTransactionID,
              let row = rows.first(where: { $0.id == id })
        else {
            matchingRules = []
            return
        }
        let description = ParsedTransactionDescription.recombine(
            title: editingDescription,
            location: editingLocation
        )
        let probe = Transaction(
            id: row.id,
            accountID: row.accountID,
            externalID: row.id.rawValue,
            amount: row.amount,
            postedDate: .now,
            description: description,
            categoryID: editingCategoryID,
            categoryLocked: editingCategoryLocked,
            tagIDs: Array(editingTagIDs),
            enrichedTitle: editingDescription,
            enrichedLocation: editingLocation
        )
        do {
            let rules = try await ruleRepository.fetchAll()
            matchingRules = CategorizationRuleMatcher.matchingRules(rules, transaction: probe)
        } catch {
            matchingRules = []
        }
    }

    func ruleSummary(for rule: CategorizationRule) -> String {
        CategorizationConditionFormatting.summary(
            for: rule.conditions,
            accountName: { [self] accountID in
                accountNames[accountID]
                    ?? accounts.first(where: { $0.id == accountID })?.name
                    ?? "Account"
            },
            tagName: { [self] tagID in
                tagNames[tagID] ?? "Tag"
            }
        )
    }

    func ruleTitle(for rule: CategorizationRule) -> String {
        if rule.appliesCategory {
            return SystemCategory.category(for: rule.categoryID).name
        }
        if let renameTitle = rule.renameTitle {
            return "Rename to “\(renameTitle)”"
        }
        return "Rename"
    }

    func ruleAppliesBadge(for rule: CategorizationRule) -> String? {
        let isWinningCategory = rule.appliesCategory
            && matchingRules.first(where: \.appliesCategory)?.id == rule.id
        let isWinningRename = rule.renameTitle != nil
            && matchingRules.first(where: { $0.renameTitle != nil })?.id == rule.id
        if isWinningCategory && isWinningRename { return "Applies" }
        if isWinningCategory { return "Category" }
        if isWinningRename { return "Rename" }
        return nil
    }

    func saveEdits() async {
        guard let id = selectedTransactionID,
              let index = rows.firstIndex(where: { $0.id == id })
        else { return }
        let storedDescription = ParsedTransactionDescription.recombine(
            title: editingDescription,
            location: editingLocation
        )
        let newCategoryID = editingCategoryID
        let locked = editingCategoryLocked
        let newTagIDs = Array(editingTagIDs).sorted { $0.rawValue < $1.rawValue }
        isSavingEdits = true
        defer { isSavingEdits = false }
        do {
            try await transactionRepository.updateCategory(
                transactionID: id,
                categoryID: newCategoryID,
                categoryLocked: locked
            )
            try await transactionRepository.updateDescription(
                transactionID: id,
                description: storedDescription
            )
            try await transactionRepository.updateTags(
                transactionID: id,
                tagIDs: newTagIDs
            )
            selectedTransactionID = nil
            editingLocation = nil

            // Active filters no longer match — drop just this row.
            if let filterCategoryID, filterCategoryID != newCategoryID {
                rows.remove(at: index)
                return
            }
            if let filterTagID, !newTagIDs.contains(filterTagID) {
                rows.remove(at: index)
                return
            }

            rows[index] = rows[index].replacing(
                description: storedDescription,
                categoryID: newCategoryID,
                categoryLocked: locked,
                tagIDs: newTagIDs,
                tagNamesByID: tagNames
            )
        } catch {
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't save changes."
            )
        }
    }

    private func refreshAccounts() async {
        do {
            accounts = try await accountRepository.fetchAll()
            accountNames = Dictionary(
                uniqueKeysWithValues: accounts.map { ($0.id, $0.name) }
            )
        } catch {
            accounts = []
        }
    }

    func refreshTags() async {
        do {
            tags = try await tagRepository.fetchAll()
            tagNames = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        } catch {
            // Keep prior tags on transient fetch failure so editor doesn't go empty.
            if tags.isEmpty {
                tagNames = [:]
            }
        }
    }
}
