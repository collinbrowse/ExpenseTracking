import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("Connection lifecycle")
struct ConnectionLifecycleTests {
    @Test("Demo link persists across fresh status reader via ConnectionEntity")
    func demoSurvivesRelaunch() async throws {
        let harness = try await makeHarness()
        _ = try await harness.lifecycle.replaceAndLink(withSetupToken: "demo")

        // Simulate process relaunch: new composite/demo session, same store.
        let relaunched = try await makeHarness(
            container: harness.container,
            accessURLStore: harness.accessURLStore
        )
        let status = await relaunched.sync.connectionStatus()
        #expect(status.isLinked)
        #expect(status.providerName == "Demo")
        #expect(status.lastSuccessfulSyncAt != nil)

        let accounts = try ModelContext(harness.container).fetch(FetchDescriptor<AccountEntity>())
        #expect(accounts.contains(where: { $0.institutionName == "Demo Bank" }))
    }

    @Test("replaceAndLink wipes prior Demo accounts before SimpleFIN sync")
    func replaceAndLinkWipesDemo() async throws {
        let harness = try await makeHarness()
        _ = try await harness.lifecycle.replaceAndLink(withSetupToken: "demo")
        let afterDemo = try ModelContext(harness.container).fetch(FetchDescriptor<AccountEntity>())
        #expect(afterDemo.contains(where: { $0.institutionName == "Demo Bank" }))

        _ = try await harness.lifecycle.replaceAndLink(withSetupToken: makeSetupToken())
        let afterSimpleFIN = try ModelContext(harness.container).fetch(FetchDescriptor<AccountEntity>())
        #expect(afterSimpleFIN.allSatisfy { $0.institutionName != "Demo Bank" })
        #expect(afterSimpleFIN.contains(where: { $0.externalID == "sf-checking" }))

        let status = await harness.sync.connectionStatus()
        #expect(status.providerName == "SimpleFIN")
        #expect(status.isLinked)
    }

    @Test("Disconnect keep leaves accounts; eraseEverything clears orphan state")
    func disconnectKeepThenErase() async throws {
        let harness = try await makeHarness()
        _ = try await harness.lifecycle.replaceAndLink(withSetupToken: "demo")
        _ = try await harness.lifecycle.disconnect(deleteLocalData: false)

        let status = await harness.sync.connectionStatus()
        #expect(!status.isLinked)

        let remaining = try ModelContext(harness.container).fetch(FetchDescriptor<AccountEntity>())
        #expect(!remaining.isEmpty)

        try await harness.lifecycle.eraseEverything()
        let cleared = try ModelContext(harness.container).fetch(FetchDescriptor<AccountEntity>())
        #expect(cleared.isEmpty)
        #expect(try harness.accessURLStore.load() == nil)
    }

    @Test("Unauthorized sync persists needsReauth on ConnectionEntity")
    func unauthorizedNeedsReauthSurvives() async throws {
        let accessStore = InMemoryAccessURLStore()
        try accessStore.save("https://user:pass@example.com/simplefin")

        let http = SimpleFINStubHTTPClient(mode: .succeedThenUnauthorized)
        let simpleFIN = SimpleFINBankLinkingService(
            client: SimpleFINClient(http: http),
            accessURLStore: accessStore
        )
        let demo = DemoBankLinkingService()
        let linking = CompositeBankLinkingService(
            demo: demo,
            simpleFIN: simpleFIN,
            initialMode: .simpleFIN
        )
        let container = try ModelContainerFactory.make(inMemory: true)
        let sync = SyncCoordinator(modelContainer: container, bankLinking: linking)

        _ = try await sync.syncNow()
        await http.armUnauthorized()
        var didFail = false
        do {
            _ = try await sync.syncNow()
        } catch CashFlowError.unauthorized {
            didFail = true
        }
        #expect(didFail)

        let relaunchedLinking = CompositeBankLinkingService(
            demo: DemoBankLinkingService(),
            simpleFIN: SimpleFINBankLinkingService(
                client: SimpleFINClient(http: SimpleFINStubHTTPClient(mode: .accountsOnly)),
                accessURLStore: accessStore
            )
        )
        let relaunchedSync = SyncCoordinator(
            modelContainer: container,
            bankLinking: relaunchedLinking
        )
        let status = await relaunchedSync.connectionStatus()
        #expect(status.isLinked)
        #expect(status.needsReauth)
        #expect(status.providerName == "SimpleFIN")
    }

    @Test("resetLocalDataKeepingLink clears rows but keeps SimpleFIN credentials")
    func resetKeepsLink() async throws {
        let harness = try await makeHarness()
        _ = try await harness.lifecycle.replaceAndLink(withSetupToken: makeSetupToken())
        _ = try await harness.lifecycle.resetLocalDataKeepingLink()

        let status = await harness.sync.connectionStatus()
        #expect(status.isLinked)
        #expect(status.providerName == "SimpleFIN")
        #expect(status.lastSuccessfulSyncAt == nil)

        let accounts = try ModelContext(harness.container).fetch(FetchDescriptor<AccountEntity>())
        #expect(accounts.isEmpty)
        #expect(try harness.accessURLStore.load() != nil)
    }
}

// MARK: - Harness

private struct LifecycleHarness {
    let container: ModelContainer
    let accessURLStore: InMemoryAccessURLStore
    let sync: SyncCoordinator
    let lifecycle: ConnectionLifecycleService
}

private func makeHarness(
    container: ModelContainer? = nil,
    accessURLStore: InMemoryAccessURLStore? = nil
) async throws -> LifecycleHarness {
    let store = accessURLStore ?? InMemoryAccessURLStore()
    let model = try container ?? ModelContainerFactory.make(inMemory: true)
    let http = SimpleFINStubHTTPClient(mode: .claimAndAccounts)
    let simpleFIN = SimpleFINBankLinkingService(
        client: SimpleFINClient(http: http),
        accessURLStore: store
    )
    let demo = DemoBankLinkingService()
    let linking = CompositeBankLinkingService(demo: demo, simpleFIN: simpleFIN)
    let sync = SyncCoordinator(modelContainer: model, bankLinking: linking)
    let resetter = LocalDataResetter(modelContainer: model)
    let lifecycle = ConnectionLifecycleService(
        bankLinking: linking,
        sync: sync,
        resetter: resetter
    )
    return LifecycleHarness(
        container: model,
        accessURLStore: store,
        sync: sync,
        lifecycle: lifecycle
    )
}

private func makeSetupToken() -> String {
    Data("https://example.com/simplefin/claim/test-token".utf8).base64EncodedString()
}

private func accountsJSON(id: String, name: String) -> Data {
    Data("""
    {"errors":[],"errlist":[],"accounts":[{"id":"\(id)","name":"\(name)","currency":"USD","balance":"10.00","balance-date":1700000000,"org":{"name":"Real Bank"},"transactions":[]}]}
    """.utf8)
}

private final class InMemoryAccessURLStore: AccessURLStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func save(_ accessURL: String) throws {
        lock.lock(); defer { lock.unlock() }
        value = accessURL
    }

    func load() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func delete() throws {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}

private actor SimpleFINStubHTTPClient: HTTPClient {
    enum Mode: Sendable {
        case claimAndAccounts
        case accountsOnly
        case succeedThenUnauthorized
    }

    private let mode: Mode
    private var unauthorizedArmed = false

    init(mode: Mode) {
        self.mode = mode
    }

    func armUnauthorized() {
        unauthorizedArmed = true
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://example.com")!
        let path = url.path

        if unauthorizedArmed, path.contains("accounts") {
            return (
                Data(),
                HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!
            )
        }

        if request.httpMethod == "POST" || path.contains("claim") {
            let data = Data("https://user:pass@example.com/simplefin".utf8)
            return (
                data,
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        if path.contains("info") {
            let data = Data("""
            {"versions":["1","2"]}
            """.utf8)
            return (
                data,
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        // Any accounts window
        return (
            accountsJSON(id: "sf-checking", name: "Checking"),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}
