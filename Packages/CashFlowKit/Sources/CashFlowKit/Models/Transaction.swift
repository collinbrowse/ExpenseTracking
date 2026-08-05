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
    /// When true, user categorization rules never change this transaction’s category.
    public let categoryLocked: Bool
    /// Local-only user tags; sync never invents or clears these.
    public let tagIDs: [TagID]

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
        isPending: Bool = false,
        categoryLocked: Bool = false,
        tagIDs: [TagID] = []
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
        self.categoryLocked = categoryLocked
        self.tagIDs = tagIDs
    }

    public var category: Category {
        SystemCategory.category(for: categoryID)
    }
}

/// Batch category write for rule re-apply (not list pagination).
public struct CategoryAssignment: Hashable, Sendable {
    public let transactionID: TransactionID
    public let categoryID: CategoryID
    public let userEditedCategory: Bool

    public init(
        transactionID: TransactionID,
        categoryID: CategoryID,
        userEditedCategory: Bool
    ) {
        self.transactionID = transactionID
        self.categoryID = categoryID
        self.userEditedCategory = userEditedCategory
    }
}
