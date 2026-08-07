import Foundation

/// Inputs for on-device category suggestion. Built in CashFlowData from txn + account metadata.
public struct CategorySuggestionRequest: Hashable, Sendable {
    public let description: String
    public let amount: Decimal
    public let currencyCode: String
    public let postedDate: Date
    public let isPending: Bool
    public let enrichedTitle: String?
    public let enrichedLocation: String?
    public let accountName: String?
    public let institutionName: String?
    /// Provisional / current category (often Undefined); context only — not a required answer.
    public let currentCategoryID: CategoryID?

    public init(
        description: String,
        amount: Decimal,
        currencyCode: String = "USD",
        postedDate: Date,
        isPending: Bool = false,
        enrichedTitle: String? = nil,
        enrichedLocation: String? = nil,
        accountName: String? = nil,
        institutionName: String? = nil,
        currentCategoryID: CategoryID? = nil
    ) {
        self.description = description
        self.amount = amount
        self.currencyCode = currencyCode
        self.postedDate = postedDate
        self.isPending = isPending
        self.enrichedTitle = enrichedTitle
        self.enrichedLocation = enrichedLocation
        self.accountName = accountName
        self.institutionName = institutionName
        self.currentCategoryID = currentCategoryID
    }

    public init(transaction: Transaction, account: Account? = nil) {
        self.init(
            description: transaction.description,
            amount: transaction.amount,
            currencyCode: transaction.currencyCode,
            postedDate: transaction.postedDate,
            isPending: transaction.isPending,
            enrichedTitle: transaction.enrichedTitle,
            enrichedLocation: transaction.enrichedLocation,
            accountName: account?.name,
            institutionName: account?.institutionName,
            currentCategoryID: transaction.categoryID
        )
    }
}
