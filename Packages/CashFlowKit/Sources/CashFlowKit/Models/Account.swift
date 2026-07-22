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
    /// Provider-reported sync problem for this account, if any. `nil` means last sync was clean.
    public let syncIssue: String?

    public init(
        id: AccountID,
        externalID: String,
        name: String,
        institutionName: String,
        currencyCode: String,
        balance: Decimal,
        balanceDate: Date,
        syncIssue: String? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.name = name
        self.institutionName = institutionName
        self.currencyCode = currencyCode
        self.balance = balance
        self.balanceDate = balanceDate
        self.syncIssue = syncIssue
    }

    public var hasSyncIssue: Bool {
        guard let syncIssue else { return false }
        return !syncIssue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
