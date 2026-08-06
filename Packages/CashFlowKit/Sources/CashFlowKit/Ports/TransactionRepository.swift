import Foundation

public protocol TransactionRepository: Sendable {
    func fetchPage(
        filter: TransactionFilter,
        cursor: TransactionCursor?,
        limit: Int
    ) async throws -> TransactionPage

    func fetchPosted(
        in range: CashFlowDateRange,
        now: Date
    ) async throws -> [Transaction]

    /// Oldest non-pending posted date, if any. Used to gate long Home ranges honestly.
    func earliestPostedDate() async throws -> Date?

    func updateCategory(
        transactionID: TransactionID,
        categoryID: CategoryID,
        categoryLocked: Bool
    ) async throws

    /// Replaces the transaction’s local tag memberships.
    func updateTags(
        transactionID: TransactionID,
        tagIDs: [TagID]
    ) async throws

    /// Store-wide write for categorization rule re-apply. Not for list UI.
    func applyCategoryAssignments(_ assignments: [CategoryAssignment]) async throws

    /// Store-wide tag membership replace for assistant confirm. Not for list UI.
    func applyTagAssignments(_ assignments: [TagAssignment]) async throws

    /// Persists local-only merchant/location enrichment. Never mutates bank description.
    /// Honors `TitleSource` precedence: lower-ranked sources cannot overwrite higher.
    /// Pass `clearLocation: true` to intentionally blank location (user edit).
    func updateEnrichment(
        transactionID: TransactionID,
        title: String,
        location: String?,
        source: TitleSource,
        clearLocation: Bool
    ) async throws

    /// Marks a row as attempted-but-unparseable so it leaves the untitled backlog.
    /// Leaves `enrichedTitle` nil (UI keeps showing raw bank text).
    func markEnrichmentSkipped(transactionID: TransactionID) async throws

    /// Batch title/location restore for rule undo.
    func applyTitleLocationAssignments(_ assignments: [TitleLocationAssignment]) async throws

    /// Posted (non-pending) transactions for rule re-apply. Not for list UI pagination.
    func fetchAllForCategorization() async throws -> [Transaction]

    /// Posted transactions missing enrichment cache (for post-sync enrichment).
    func fetchNeedingEnrichment(limit: Int) async throws -> [Transaction]

    /// Count of posted transactions still missing a title.
    func countNeedingEnrichment() async throws -> Int

    /// Distinct normalized bank descriptions still lacking enrichment (memo-cache work units).
    func countDistinctDescriptionsNeedingEnrichment() async throws -> Int
}

public protocol AccountRepository: Sendable {
    func fetchAll() async throws -> [Account]

    /// Persists a local display name; subsequent syncs keep it while the account still matches.
    func updateName(accountID: AccountID, name: String) async throws
}
