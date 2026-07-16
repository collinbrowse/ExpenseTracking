import Foundation

public struct TransactionID: Hashable, Sendable, Codable, Comparable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TransactionID, rhs: TransactionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Transaction: Identifiable, Hashable, Sendable, Codable {
    public let id: TransactionID
    public let accountID: AccountID
    public let externalID: String
    public let amount: Decimal
    public let postedDate: Date
    public let description: String
    public let categoryID: CategoryID
    public let currencyCode: String
    public let userEditedCategory: Bool
    public let isPending: Bool

    public init(
        id: TransactionID,
        accountID: AccountID,
        externalID: String,
        amount: Decimal,
        postedDate: Date,
        description: String,
        categoryID: CategoryID,
        currencyCode: String = "USD",
        userEditedCategory: Bool = false,
        isPending: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.externalID = externalID
        self.amount = amount
        self.postedDate = postedDate
        self.description = description
        self.categoryID = categoryID
        self.currencyCode = currencyCode
        self.userEditedCategory = userEditedCategory
        self.isPending = isPending
    }

    public var category: Category {
        SystemCategory.category(for: categoryID)
    }
}
