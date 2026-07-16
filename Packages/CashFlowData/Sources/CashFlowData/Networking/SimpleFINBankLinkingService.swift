import Foundation
import CashFlowKit

public actor SimpleFINBankLinkingService: BankLinkingServing {
    public let providerName = "SimpleFIN"

    private let client: SimpleFINClient
    private let accessURLStore: any AccessURLStoring
    private var needsReauth = false
    private var lastSuccessfulSyncAt: Date?

    public init(
        client: SimpleFINClient = SimpleFINClient(),
        accessURLStore: any AccessURLStoring = KeychainAccessURLStore()
    ) {
        self.client = client
        self.accessURLStore = accessURLStore
    }

    public func connectionStatus() async -> LinkedConnection {
        let linked = (try? accessURLStore.load()) != nil
        return LinkedConnection(
            isLinked: linked,
            providerName: providerName,
            needsReauth: needsReauth,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt
        )
    }

    public func link(withSetupToken token: String) async throws {
        let accessURL = try await client.claimAccessURL(setupToken: token)
        try accessURLStore.save(accessURL)
        needsReauth = false
        _ = try? await client.fetchInfo(accessURL: accessURL)
    }

    public func unlink(removeLocalData: Bool) async throws {
        _ = removeLocalData
        try accessURLStore.delete()
        needsReauth = false
        lastSuccessfulSyncAt = nil
    }

    public func fetchAccounts(
        startDate: Date?,
        endDate: Date?
    ) async throws -> RemoteSyncPayload {
        guard let accessURL = try accessURLStore.load() else {
            throw CashFlowError.notLinked
        }
        do {
            let payload = try await client.fetchAccounts(
                accessURL: accessURL,
                startDate: startDate,
                endDate: endDate
            )
            lastSuccessfulSyncAt = .now
            needsReauth = false
            return payload
        } catch CashFlowError.unauthorized {
            needsReauth = true
            throw CashFlowError.unauthorized
        }
    }

    public func markSynced(at date: Date = .now) {
        lastSuccessfulSyncAt = date
    }
}
