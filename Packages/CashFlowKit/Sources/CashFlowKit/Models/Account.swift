import Foundation

public struct AccountID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct Account: Identifiable, Hashable, Sendable, Codable {
    public let id: AccountID
    public let externalID: String
    public let name: String
    public let institutionName: String
    public let currencyCode: String
    public let balance: Decimal
    public let balanceDate: Date

    public init(
        id: AccountID,
        externalID: String,
        name: String,
        institutionName: String,
        currencyCode: String,
        balance: Decimal,
        balanceDate: Date
    ) {
        self.id = id
        self.externalID = externalID
        self.name = name
        self.institutionName = institutionName
        self.currencyCode = currencyCode
        self.balance = balance
        self.balanceDate = balanceDate
    }
}
