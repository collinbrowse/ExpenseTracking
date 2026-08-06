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
    /// SimpleFIN Bridge `conn_id` when present (used to attach connection-scoped errors).
    public let connectionExternalID: String?
    /// Provider error for this account from the latest fetch, if any.
    public let syncIssue: String?

    public init(
        externalID: String,
        name: String,
        institutionName: String,
        currencyCode: String,
        balance: Decimal,
        balanceDate: Date,
        transactions: [RemoteTransactionSnapshot],
        connectionExternalID: String? = nil,
        syncIssue: String? = nil
    ) {
        self.externalID = externalID
        self.name = name
        self.institutionName = institutionName
        self.currencyCode = currencyCode
        self.balance = balance
        self.balanceDate = balanceDate
        self.transactions = transactions
        self.connectionExternalID = connectionExternalID
        self.syncIssue = syncIssue
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

    /// Live sync progress. Yields the latest value on subscribe when a sync is in flight;
    /// yields `nil` when idle. Overlapping `syncNow` callers share one sync and one stream.
    func syncProgressUpdates() -> AsyncStream<SyncProgress?>

    /// Consumes a one-shot enrichment prompt produced after a large first sync.
    func consumePendingEnrichmentPrompt() async -> EnrichmentWorkEstimate?

    /// Durable multi-day history + title cleanup status for Settings.
    func historyImportStatus() async -> HistoryImportStatus?

    /// Updates the stored lookback target; deeper targets re-open backward walk only.
    func setHistoryLookback(_ lookback: HistoryLookbackYears) async throws
}

extension SyncServing {
    public func syncProgressUpdates() -> AsyncStream<SyncProgress?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }

    public func consumePendingEnrichmentPrompt() async -> EnrichmentWorkEstimate? { nil }

    public func historyImportStatus() async -> HistoryImportStatus? { nil }

    public func setHistoryLookback(_ lookback: HistoryLookbackYears) async throws {}
}
