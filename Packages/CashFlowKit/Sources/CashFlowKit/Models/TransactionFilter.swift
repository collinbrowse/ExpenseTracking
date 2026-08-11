import Foundation

public struct TransactionFilter: Hashable, Sendable {
    public var accountID: AccountID?
    public var dateRange: CashFlowDateRange?
    public var categoryID: CategoryID?
    public var tagID: TagID?
    /// Trimmed free-text query applied at the repository layer (store-wide keyset scan).
    public var searchQuery: String?

    public init(
        accountID: AccountID? = nil,
        dateRange: CashFlowDateRange? = nil,
        categoryID: CategoryID? = nil,
        tagID: TagID? = nil,
        searchQuery: String? = nil
    ) {
        self.accountID = accountID
        self.dateRange = dateRange
        self.categoryID = categoryID
        self.tagID = tagID
        let trimmed = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.searchQuery = trimmed.isEmpty ? nil : trimmed
    }

    public static let all = TransactionFilter()
}

public struct TransactionCursor: Hashable, Sendable {
    public let postedDate: Date
    public let id: TransactionID

    public init(postedDate: Date, id: TransactionID) {
        self.postedDate = postedDate
        self.id = id
    }

    public init(transaction: Transaction) {
        self.postedDate = transaction.postedDate
        self.id = transaction.id
    }
}

public struct TransactionPage: Sendable {
    public let items: [Transaction]
    public let nextCursor: TransactionCursor?

    public init(items: [Transaction], nextCursor: TransactionCursor?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    public var hasMore: Bool { nextCursor != nil }
}

public enum TransactionPageSize {
    public static let `default` = 50
}
