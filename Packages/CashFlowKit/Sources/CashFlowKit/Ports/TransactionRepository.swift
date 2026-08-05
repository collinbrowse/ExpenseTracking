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

    func updateDescription(
        transactionID: TransactionID,
        description: String
    ) async throws

    /// Replaces the transaction’s local tag memberships.
    func updateTags(
        transactionID: TransactionID,
        tagIDs: [TagID]
    ) async throws

    /// Store-wide write for categorization rule re-apply. Not for list UI.
    func applyCategoryAssignments(_ assignments: [CategoryAssignment]) async throws

    /// Posted (non-pending) transactions for rule re-apply. Not for list UI pagination.
    func fetchAllForCategorization() async throws -> [Transaction]
}

public protocol AccountRepository: Sendable {
    func fetchAll() async throws -> [Account]

    /// Persists a local display name; subsequent syncs keep it while the account still matches.
    func updateName(accountID: AccountID, name: String) async throws
}
