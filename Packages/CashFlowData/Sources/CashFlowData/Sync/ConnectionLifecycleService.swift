import Foundation
import CashFlowKit

/// Atomic link / disconnect / erase / reset. Composes sync + resetter + bank linking (SRP).
public actor ConnectionLifecycleService: ConnectionLifecycleServing {
    private let bankLinking: CompositeBankLinkingService
    private let sync: SyncCoordinator
    private let resetter: LocalDataResetter

    public init(
        bankLinking: CompositeBankLinkingService,
        sync: SyncCoordinator,
        resetter: LocalDataResetter
    ) {
        self.bankLinking = bankLinking
        self.sync = sync
        self.resetter = resetter
    }

    public func replaceAndLink(withSetupToken token: String) async throws -> LinkedConnection {
        await sync.cancel()
        // Wipe first so provider switches never merge Demo + SimpleFIN rows.
        try await resetter.resetAll()
        try? await bankLinking.unlink(removeLocalData: false)
        try await bankLinking.link(withSetupToken: token)
        return try await sync.syncNow()
    }

    public func disconnect(deleteLocalData: Bool) async throws -> LinkedConnection {
        await sync.cancel()
        if deleteLocalData {
            // Wipe before unlink so a failed wipe can be retried while still linked.
            try await resetter.resetAll()
            try await bankLinking.unlink(removeLocalData: false)
        } else {
            try await bankLinking.unlink(removeLocalData: false)
            try await resetter.clearConnection()
        }
        return await sync.connectionStatus()
    }

    public func eraseEverything() async throws {
        await sync.cancel()
        try? await bankLinking.unlink(removeLocalData: false)
        try await resetter.resetAll()
        try await resetter.deleteAllCategorizationRules()
        try await resetter.deleteAllTags()
    }

    public func resetLocalDataKeepingLink() async throws -> LinkedConnection {
        await sync.cancel()
        let prior = await sync.connectionStatus()
        try await resetter.resetAll()
        if prior.isLinked {
            try await resetter.upsertConnectionPlaceholder(
                providerName: prior.providerName,
                isDemo: prior.providerName == "Demo"
            )
            if prior.providerName == "Demo" {
                await bankLinking.adoptDurableDemoLink()
            }
        }
        return await sync.connectionStatus()
    }
}
