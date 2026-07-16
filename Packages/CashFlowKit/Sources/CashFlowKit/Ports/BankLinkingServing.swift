import Foundation

public struct LinkedConnection: Sendable, Equatable {
    public let isLinked: Bool
    public let providerName: String
    public let needsReauth: Bool
    public let lastSuccessfulSyncAt: Date?
    public let providerMessages: [String]

    public init(
        isLinked: Bool,
        providerName: String,
        needsReauth: Bool = false,
        lastSuccessfulSyncAt: Date? = nil,
        providerMessages: [String] = []
    ) {
        self.isLinked = isLinked
        self.providerName = providerName
        self.needsReauth = needsReauth
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.providerMessages = providerMessages
    }
}

public struct RemoteAccountSnapshot: Sendable, Equatable {
    public let externalID: String
    public let name: String
    public let institutionName: String
    public let currencyCode: String
    public let balance: Decimal
    public let balanceDate: Date
    public let transactions: [RemoteTransactionSnapshot]

    public init(
        externalID: String,
        name: String,
        institutionName: String,
        currencyCode: String,
        balance: Decimal,
        balanceDate: Date,
        transactions: [RemoteTransactionSnapshot]
    ) {
        self.externalID = externalID
        self.name = name
        self.institutionName = institutionName
        self.currencyCode = currencyCode
        self.balance = balance
        self.balanceDate = balanceDate
        self.transactions = transactions
    }
}

public struct RemoteTransactionSnapshot: Sendable, Equatable {
    public let externalID: String
    public let amount: Decimal
    public let postedDate: Date
    public let description: String
    public let isPending: Bool
    public let suggestedCategoryID: CategoryID

    public init(
        externalID: String,
        amount: Decimal,
        postedDate: Date,
        description: String,
        isPending: Bool = false,
        suggestedCategoryID: CategoryID = SystemCategory.other.id
    ) {
        self.externalID = externalID
        self.amount = amount
        self.postedDate = postedDate
        self.description = description
        self.isPending = isPending
        self.suggestedCategoryID = suggestedCategoryID
    }
}

public struct RemoteSyncPayload: Sendable, Equatable {
    public let accounts: [RemoteAccountSnapshot]
    public let providerMessages: [String]

    public init(accounts: [RemoteAccountSnapshot], providerMessages: [String] = []) {
        self.accounts = accounts
        self.providerMessages = providerMessages
    }
}

public protocol BankLinkingServing: Sendable {
    var providerName: String { get }

    func connectionStatus() async -> LinkedConnection

    /// Claim a SimpleFIN setup token (base64) or enable demo mode.
    func link(withSetupToken token: String) async throws

    func unlink(removeLocalData: Bool) async throws

    func fetchAccounts(
        startDate: Date?,
        endDate: Date?
    ) async throws -> RemoteSyncPayload
}

public protocol SyncServing: Sendable {
    func syncNow() async throws -> LinkedConnection
    func connectionStatus() async -> LinkedConnection
}
