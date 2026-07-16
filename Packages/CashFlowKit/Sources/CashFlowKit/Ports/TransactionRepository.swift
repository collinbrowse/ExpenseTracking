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

    func updateCategory(
        transactionID: TransactionID,
        categoryID: CategoryID
    ) async throws

    func updateDescription(
        transactionID: TransactionID,
        description: String
    ) async throws
}

public protocol AccountRepository: Sendable {
    func fetchAll() async throws -> [Account]
}
