import Foundation
import Observation
import CashFlowKit
import CashFlowData

struct ActiveFilterChip: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case account
        case date
        case category
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
    private let syncServing: any SyncServing

    var rows: [TransactionRowModel] = []
    var accounts: [Account] = []
    var searchText = ""
    var filterAccountID: AccountID?
    var filterCategoryID: CategoryID?
    var filterDateOption: TransactionDateFilterOption = .all
    var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    var customEnd: Date = .now
    var showFilters = false
    var showCustomRange = false
    var isLoadingPage = false
    var hasMore = true
    var bannerMessage: String?
    var selectedTransactionID: TransactionID?
    var editingDescription = ""
    var editingCategoryID: CategoryID = SystemCategory.other.id
    var editingAccountName = ""
    var editingLocation: String?

    private var cursor: TransactionCursor?
    private var loadTask: Task<Void, Never>?
    private var accountNames: [AccountID: String] = [:]

    init(
        transactionRepository: any TransactionRepository,
        accountRepository: any AccountRepository,
        syncServing: any SyncServing
    ) {
        self.transactionRepository = transactionRepository
        self.accountRepository = accountRepository
        self.syncServing = syncServing
    }

    var filter: TransactionFilter {
        TransactionFilter(
            accountID: filterAccountID,
            dateRange: filterDateOption.dateRange(
                customStart: customStart,
                customEnd: customEnd
            ),
            categoryID: filterCategoryID
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
        return chips
    }

    var displayedRows: [TransactionRowModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            row.title.localizedCaseInsensitiveContains(query)
                || row.location?.localizedCaseInsensitiveContains(query) == true
                || row.categoryText.localizedCaseInsensitiveContains(query)
                || row.accountName.localizedCaseInsensitiveContains(query)
                || TransactionAmountSearch.matches(query, amountText: row.amountText)
        }
    }

    /// Month sections in descending chronological order (already sorted in `rows`).
    var sections: [TransactionMonthSection] {
        var orderedKeys: [String] = []
        var buckets: [String: [TransactionRowModel]] = [:]
        var titles: [String: String] = [:]

        for row in displayedRows {
            if buckets[row.sectionKey] == nil {
                orderedKeys.append(row.sectionKey)
                titles[row.sectionKey] = row.sectionTitle
                buckets[row.sectionKey] = []
            }
            buckets[row.sectionKey]?.append(row)
        }

        return orderedKeys.compactMap { key in
            guard let rows = buckets[key], let title = titles[key] else { return nil }
            return TransactionMonthSection(key: key, title: title, rows: rows)
        }
    }

    func onAppear() async {
        await refreshAccounts()
        await resetAndLoad()
    }

    func applyFilters() async {
        showFilters = false
        await resetAndLoad()
    }

    /// Opens the list focused on one account (from Accounts tab).
    func focusAccount(_ accountID: AccountID) async {
        filterAccountID = accountID
        filterCategoryID = nil
        filterDateOption = .all
        await refreshAccounts()
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
        }
        await resetAndLoad()
    }

    func clearAllFilters() async {
        filterAccountID = nil
        filterCategoryID = nil
        filterDateOption = .all
        await resetAndLoad()
    }

    func resetAndLoad() async {
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
                    accountName: accountNames[tx.accountID] ?? "Account"
                )
            }
            rows.append(contentsOf: mapped)
            cursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            bannerMessage = "Couldn't load transactions."
        }
    }

    func refresh() async {
        do {
            _ = try await syncServing.syncNow()
            bannerMessage = nil
        } catch {
            bannerMessage = "Couldn't refresh. Showing last saved data."
        }
        await refreshAccounts()
        await resetAndLoad()
    }

    func openEditor(for id: TransactionID) {
        selectedTransactionID = id
        if let row = rows.first(where: { $0.id == id }) {
            editingDescription = row.title
            editingCategoryID = row.categoryID
            editingAccountName = row.accountName
            editingLocation = row.location
        }
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
        do {
            try await transactionRepository.updateCategory(
                transactionID: id,
                categoryID: newCategoryID
            )
            try await transactionRepository.updateDescription(
                transactionID: id,
                description: storedDescription
            )
            selectedTransactionID = nil
            editingLocation = nil

            // Category filter no longer matches — drop just this row.
            if let filterCategoryID, filterCategoryID != newCategoryID {
                rows.remove(at: index)
                return
            }

            rows[index] = rows[index].replacing(
                description: storedDescription,
                categoryID: newCategoryID
            )
        } catch {
            bannerMessage = "Couldn't save changes."
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
}
