import Foundation
import Observation
import CashFlowKit

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

/// Single source of truth for Transactions list filters and CSV export filters.
/// Owned by `RootTabView` and shared so both surfaces stay in sync.
@MainActor
@Observable
final class TransactionFilterSession {
    var accountID: AccountID? {
        didSet { bumpUnlessBulk() }
    }
    var categoryID: CategoryID? {
        didSet { bumpUnlessBulk() }
    }
    var tagID: TagID? {
        didSet { bumpUnlessBulk() }
    }
    var dateOption: TransactionDateFilterOption = .all {
        didSet { bumpUnlessBulk() }
    }
    var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now {
        didSet { bumpUnlessBulk() }
    }
    var customEnd: Date = .now {
        didSet { bumpUnlessBulk() }
    }
    var searchText = "" {
        didSet { scheduleSearchCommit() }
    }

    /// Committed search query used by `filter` (debounced from `searchText`).
    private(set) var appliedSearchQuery: String?
    /// Bumped whenever the effective filter changes so list/export observers can reload.
    private(set) var revision: UInt64 = 0

    var showFiltersSheet = false

    private var bulkUpdating = false
    private var searchTask: Task<Void, Never>?
    private var searchEnabled = false

    var filter: TransactionFilter {
        TransactionFilter(
            accountID: accountID,
            dateRange: dateOption.dateRange(customStart: customStart, customEnd: customEnd),
            categoryID: categoryID,
            tagID: tagID,
            searchQuery: appliedSearchQuery
        )
    }

    var hasActiveFilters: Bool {
        accountID != nil
            || categoryID != nil
            || tagID != nil
            || dateOption != .all
            || appliedSearchQuery != nil
    }

    /// Enable search debounce after the first list load so launch does not double-fetch.
    func enableSearchDebounce() {
        searchEnabled = true
    }

    func activeFilterChips(
        accountNames: [AccountID: String],
        accounts: [Account],
        tagNames: [TagID: String],
        tags: [Tag]
    ) -> [ActiveFilterChip] {
        var chips: [ActiveFilterChip] = []
        if let accountID {
            let name = accountNames[accountID]
                ?? accounts.first(where: { $0.id == accountID })?.name
                ?? "Account"
            chips.append(ActiveFilterChip(kind: .account, label: name))
        }
        if dateOption != .all {
            let label: String
            if dateOption == .custom {
                label = "\(DateFormatting.list(customStart)) – \(DateFormatting.list(customEnd))"
            } else {
                label = dateOption.title
            }
            chips.append(ActiveFilterChip(kind: .date, label: label))
        }
        if let categoryID {
            chips.append(
                ActiveFilterChip(
                    kind: .category,
                    label: SystemCategory.category(for: categoryID).name
                )
            )
        }
        if let tagID {
            chips.append(
                ActiveFilterChip(
                    kind: .tag,
                    label: tagNames[tagID]
                        ?? tags.first(where: { $0.id == tagID })?.name
                        ?? "Tag"
                )
            )
        }
        return chips
    }

    func clear(_ kind: ActiveFilterChip.Kind) {
        switch kind {
        case .account: accountID = nil
        case .date: dateOption = .all
        case .category: categoryID = nil
        case .tag: tagID = nil
        }
    }

    func clearAll() {
        performBulk {
            accountID = nil
            categoryID = nil
            tagID = nil
            dateOption = .all
            searchText = ""
            appliedSearchQuery = nil
        }
    }

    func focusAccount(_ accountID: AccountID) {
        performBulk {
            self.accountID = accountID
            categoryID = nil
            tagID = nil
            dateOption = .all
            searchText = ""
            appliedSearchQuery = nil
        }
    }

    func focusInsights(
        categoryID: CategoryID?,
        tagID: TagID?,
        dateOption: TransactionDateFilterOption,
        customStart: Date,
        customEnd: Date
    ) {
        performBulk {
            accountID = nil
            self.categoryID = categoryID
            self.tagID = tagID
            self.dateOption = dateOption
            self.customStart = customStart
            self.customEnd = customEnd
            searchText = ""
            appliedSearchQuery = nil
        }
    }

    private func performBulk(_ body: () -> Void) {
        bulkUpdating = true
        body()
        bulkUpdating = false
        bump()
    }

    private func bumpUnlessBulk() {
        guard !bulkUpdating else { return }
        bump()
    }

    private func bump() {
        revision &+= 1
    }

    private func scheduleSearchCommit() {
        guard searchEnabled else { return }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = trimmed.isEmpty ? nil : trimmed
        guard next != appliedSearchQuery else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, let self else { return }
            let latest = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let applied = latest.isEmpty ? nil : latest
            guard applied != self.appliedSearchQuery else { return }
            self.appliedSearchQuery = applied
            self.bump()
        }
    }
}
