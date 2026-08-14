import Foundation
import Observation
import CashFlowKit
import CashFlowData

@MainActor
@Observable
final class TransactionsViewModel {
    private let transactionRepository: any TransactionRepository
    private let accountRepository: any AccountRepository
    private let tagRepository: any TagRepository
    private let syncServing: any SyncServing

    let filters: TransactionFilterSession
    let editor: TransactionEditorSession

    var rows: [TransactionRowModel] = []
    var accounts: [Account] = [] {
        didSet { syncEditorCaches() }
    }
    var tags: [CashFlowKit.Tag] = [] {
        didSet { syncEditorCaches() }
    }
    var showCustomRange = false
    var isLoadingPage = false
    var hasMore = true
    var bannerMessage: String?
    var syncProgress: SyncProgress?

    /// Convenience accessors for list bindings / chips.
    var searchText: String {
        get { filters.searchText }
        set { filters.searchText = newValue }
    }
    var showFilters: Bool {
        get { filters.showFiltersSheet }
        set { filters.showFiltersSheet = newValue }
    }
    var filterAccountID: AccountID? {
        get { filters.accountID }
        set { filters.accountID = newValue }
    }
    var filterCategoryID: CategoryID? {
        get { filters.categoryID }
        set { filters.categoryID = newValue }
    }
    var filterTagID: TagID? {
        get { filters.tagID }
        set { filters.tagID = newValue }
    }
    var filterDateOption: TransactionDateFilterOption {
        get { filters.dateOption }
        set { filters.dateOption = newValue }
    }
    var customStart: Date {
        get { filters.customStart }
        set { filters.customStart = newValue }
    }
    var customEnd: Date {
        get { filters.customEnd }
        set { filters.customEnd = newValue }
    }

    var selectedTransactionID: TransactionID? {
        get { editor.selectedTransactionID }
        set { editor.selectedTransactionID = newValue }
    }
    var editingDescription: String {
        get { editor.editingDescription }
        set { editor.editingDescription = newValue }
    }
    var editingCategoryID: CategoryID {
        get { editor.editingCategoryID }
        set { editor.editingCategoryID = newValue }
    }
    var editingCategoryLocked: Bool {
        get { editor.editingCategoryLocked }
        set { editor.editingCategoryLocked = newValue }
    }
    var editingTagIDs: Set<TagID> {
        get { editor.editingTagIDs }
        set { editor.editingTagIDs = newValue }
    }
    var editingAccountName: String {
        get { editor.editingAccountName }
        set { editor.editingAccountName = newValue }
    }
    var editingLocation: String {
        get { editor.editingLocation }
        set { editor.editingLocation = newValue }
    }
    var editingAmountText: String {
        get { editor.editingAmountText }
        set { editor.editingAmountText = newValue }
    }
    var editingAmountIsIncome: Bool {
        get { editor.editingAmountIsIncome }
        set { editor.editingAmountIsIncome = newValue }
    }
    var editingRawDescription: String {
        get { editor.editingRawDescription }
        set { editor.editingRawDescription = newValue }
    }
    var editingIngestSourceLabel: String? {
        switch editor.editingIngestSource {
        case .bankLink: return nil
        case .csvImport: return "Imported from CSV"
        }
    }
    var newTagName: String {
        get { editor.newTagName }
        set { editor.newTagName = newValue }
    }
    var matchingRules: [CategorizationRule] {
        get { editor.matchingRules }
        set { editor.matchingRules = newValue }
    }
    var showRuleEditor: Bool {
        get { editor.showRuleEditor }
        set { editor.showRuleEditor = newValue }
    }
    var ruleEditor: CategorizationRuleEditorViewModel? {
        get { editor.ruleEditor }
        set { editor.ruleEditor = newValue }
    }
    var isSavingEdits: Bool {
        get { editor.isSavingEdits }
        set { editor.isSavingEdits = newValue }
    }

    private var cursor: TransactionCursor?
    private var loadTask: Task<Void, Never>?
    private var accountNames: [AccountID: String] = [:] {
        didSet { syncEditorCaches() }
    }
    private var tagNames: [TagID: String] = [:] {
        didSet { syncEditorCaches() }
    }
    private var syncProgressTask: Task<Void, Never>?
    private var lastHandledFilterRevision: UInt64 = 0

    init(
        filters: TransactionFilterSession,
        transactionRepository: any TransactionRepository,
        accountRepository: any AccountRepository,
        tagRepository: any TagRepository,
        syncServing: any SyncServing,
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        ruleDrafting: (any CategorizationRuleDrafting)? = nil,
        availabilityChecker: (any OnDeviceModelAvailabilityChecking)? = nil
    ) {
        self.filters = filters
        self.transactionRepository = transactionRepository
        self.accountRepository = accountRepository
        self.tagRepository = tagRepository
        self.syncServing = syncServing
        let editor = TransactionEditorSession(
            transactionRepository: transactionRepository,
            accountRepository: accountRepository,
            tagRepository: tagRepository,
            ruleRepository: ruleRepository,
            ruleApplying: ruleApplying,
            ruleDrafting: ruleDrafting,
            availabilityChecker: availabilityChecker
        )
        self.editor = editor
        editor.listRow = { [weak self] id in self?.rows.first(where: { $0.id == id }) }
        editor.applyListRow = { [weak self] row in
            guard let self, let index = self.rows.firstIndex(where: { $0.id == row.id }) else { return }
            self.rows[index] = row
        }
        editor.removeListRow = { [weak self] id in
            self?.rows.removeAll { $0.id == id }
        }
        editor.reloadList = { [weak self] in
            await self?.resetAndLoad()
        }
        editor.filterCategoryID = { [weak self] in self?.filters.categoryID }
        editor.filterTagID = { [weak self] in self?.filters.tagID }
        editor.presentBanner = { [weak self] message in
            self?.bannerMessage = message
        }
    }

    private func syncEditorCaches() {
        editor.accounts = accounts
        editor.tags = tags
        editor.accountNames = accountNames
        editor.tagNames = tagNames
    }

    var filter: TransactionFilter { filters.filter }

    var hasActiveFilters: Bool { filters.hasActiveFilters }

    /// Visible summary of non-default filters (account / date / category / tag).
    var activeFilterChips: [ActiveFilterChip] {
        filters.activeFilterChips(
            accountNames: accountNames,
            accounts: accounts,
            tagNames: tagNames,
            tags: tags
        )
    }

    /// Rows already filtered by the repository (including search).
    var displayedRows: [TransactionRowModel] { rows }

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
        lastHandledFilterRevision = filters.revision
        filters.enableSearchDebounce()
        await resetAndLoad()
    }

    /// Reloads when the shared filter session changes (list or export UI).
    func handleFilterRevisionChange() async {
        guard hasLoadedOnce else { return }
        guard filters.revision != lastHandledFilterRevision else { return }
        lastHandledFilterRevision = filters.revision
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

    func applyFilters() {
        showFilters = false
    }

    /// Opens the list focused on one account (from Accounts tab).
    func focusAccount(_ accountID: AccountID) async {
        filters.focusAccount(accountID)
        await refreshAccounts()
        await refreshTags()
        hasLoadedOnce = true
        filters.enableSearchDebounce()
        lastHandledFilterRevision = filters.revision
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
        filters.focusInsights(
            categoryID: categoryID,
            tagID: tagID,
            dateOption: dateOption,
            customStart: customStart,
            customEnd: customEnd
        )
        await refreshAccounts()
        await refreshTags()
        hasLoadedOnce = true
        filters.enableSearchDebounce()
        lastHandledFilterRevision = filters.revision
        await resetAndLoad()
    }

    func clearFilter(_ kind: ActiveFilterChip.Kind) {
        filters.clear(kind)
    }

    func clearAllFilters() {
        filters.clearAll()
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
        editor.open(for: id)
    }

    /// Call when the Transactions tab becomes active so newly created Insights tags appear.
    func refreshTagsIfNeeded() async {
        await refreshTags()
    }

    func toggleEditingTag(_ tagID: TagID) {
        editor.toggleEditingTag(tagID)
    }

    func createTagFromEditor() async {
        await editor.createTagFromEditor()
        tags = editor.tags
        tagNames = editor.tagNames
    }

    func presentCreateRule() {
        editor.presentCreateRule()
    }

    func presentEditRule(_ rule: CategorizationRule) {
        editor.presentEditRule(rule)
    }

    func handleRuleEditorDismissed() async {
        await editor.handleRuleEditorDismissed()
    }

    func scheduleMatchingRulesRefresh() {
        editor.scheduleMatchingRulesRefresh()
    }

    func refreshMatchingRules() async {
        await editor.refreshMatchingRules()
    }

    func ruleSummary(for rule: CategorizationRule) -> String {
        editor.ruleSummary(for: rule)
    }

    func ruleTitle(for rule: CategorizationRule) -> String {
        editor.ruleTitle(for: rule)
    }

    func ruleAppliesBadge(for rule: CategorizationRule) -> String? {
        editor.ruleAppliesBadge(for: rule)
    }

    func saveEdits() async {
        await editor.saveEdits()
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
            if tags.isEmpty {
                tagNames = [:]
            }
        }
        syncEditorCaches()
    }
}
