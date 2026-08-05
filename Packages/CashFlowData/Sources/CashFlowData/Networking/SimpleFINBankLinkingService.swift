import Foundation
import CashFlowKit

public actor SimpleFINBankLinkingService: BankLinkingServing {
    public let providerName = "SimpleFIN"

    private let client: SimpleFINClient
    private let accessURLStore: any AccessURLStoring
    private var needsReauth = false

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
            lastSuccessfulSyncAt: nil
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
    }

    public func fetchAccounts(
        startDate: Date?,
        endDate: Date?
    ) async throws -> RemoteSyncPayload {
        try await fetchAccounts(startDate: startDate, endDate: endDate, onWindowProgress: nil)
    }

    public func fetchAccounts(
        startDate: Date?,
        endDate: Date?,
        onWindowProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async throws -> RemoteSyncPayload {
        guard let accessURL = try accessURLStore.load() else {
            throw CashFlowError.notLinked
        }
        do {
            let payload = try await client.fetchAccounts(
                accessURL: accessURL,
                startDate: startDate,
                endDate: endDate,
                onWindowProgress: onWindowProgress
            )
            // Watermark / lastSuccessfulSyncAt are owned by SyncCoordinator + ConnectionEntity.
            needsReauth = false
            return payload
        } catch CashFlowError.unauthorized {
            needsReauth = true
            throw CashFlowError.unauthorized
        }
    }
}
