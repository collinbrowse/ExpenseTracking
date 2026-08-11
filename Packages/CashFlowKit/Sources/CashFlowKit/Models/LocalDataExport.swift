import Foundation

/// Versioned portable ledger snapshot (independent of SwiftData schema version).
public struct LocalDataExportDocument: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let exportedAt: Date
    public let accounts: [LocalDataExportAccount]
    public let transactions: [Transaction]
    public let tags: [Tag]
    public let rules: [CategorizationRule]
    public let connection: LocalDataExportConnection?

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        exportedAt: Date,
        accounts: [LocalDataExportAccount],
        transactions: [Transaction],
        tags: [Tag],
        rules: [CategorizationRule],
        connection: LocalDataExportConnection?
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.accounts = accounts
        self.transactions = transactions
        self.tags = tags
        self.rules = rules
        self.connection = connection
    }
}

public struct LocalDataExportAccount: Codable, Sendable, Equatable {
    public let id: AccountID
    public let externalID: String
    public let name: String
    public let institutionName: String
    public let currencyCode: String
    public let balance: Decimal
    public let balanceDate: Date
    public let syncIssue: String?
    public let userEditedName: Bool
    public let connectionExternalID: String?

    public init(
        id: AccountID,
        externalID: String,
        name: String,
        institutionName: String,
        currencyCode: String,
        balance: Decimal,
        balanceDate: Date,
        syncIssue: String?,
        userEditedName: Bool,
        connectionExternalID: String?
    ) {
        self.id = id
        self.externalID = externalID
        self.name = name
        self.institutionName = institutionName
        self.currencyCode = currencyCode
        self.balance = balance
        self.balanceDate = balanceDate
        self.syncIssue = syncIssue
        self.userEditedName = userEditedName
        self.connectionExternalID = connectionExternalID
    }
}

/// Connection metadata only — never includes Keychain access URLs or secrets.
public struct LocalDataExportConnection: Codable, Sendable, Equatable {
    public let id: String
    public let providerName: String
    public let needsReauth: Bool
    public let lastSuccessfulSyncAt: Date?
    public let isDemo: Bool
    public let earliestFetchedDate: Date?
    public let lookbackYears: Int
    public let historyComplete: Bool

    public init(
        id: String,
        providerName: String,
        needsReauth: Bool,
        lastSuccessfulSyncAt: Date?,
        isDemo: Bool,
        earliestFetchedDate: Date?,
        lookbackYears: Int,
        historyComplete: Bool
    ) {
        self.id = id
        self.providerName = providerName
        self.needsReauth = needsReauth
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.isDemo = isDemo
        self.earliestFetchedDate = earliestFetchedDate
        self.lookbackYears = lookbackYears
        self.historyComplete = historyComplete
    }
}
