import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("Sync history backfill")
struct SyncHistoryBackfillTests {
    @Test("Watermark alone does not skip lookback until historyBackfillComplete")
    func incompleteBackfillIgnoresWatermark() async throws {
        let accessStore = InMemoryAccessURLStore()
        try accessStore.save("https://user:pass@example.com/simplefin")

        let http = RecordingAccountsHTTPClient()
        let linking = CompositeBankLinkingService(
            demo: DemoBankLinkingService(),
            simpleFIN: SimpleFINBankLinkingService(
                client: SimpleFINClient(http: http),
                accessURLStore: accessStore
            ),
            initialMode: .simpleFIN
        )
        let container = try ModelContainerFactory.make(inMemory: true)

        let seed = ModelContext(container)
        seed.insert(
            ConnectionEntity(
                providerName: "SimpleFIN",
                needsReauth: false,
                lastSuccessfulSyncAt: .now,
                isDemo: false,
                historyBackfillComplete: false
            )
        )
        try seed.save()

        let sync = SyncCoordinator(modelContainer: container, bankLinking: linking)
        _ = try await sync.syncNow()

        let earliest = await http.earliestRequestedStart()
        let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: .now)!
        #expect(earliest != nil)
        #expect(abs(earliest!.timeIntervalSince(twoYearsAgo)) < 172_800)

        let afterBackfill = try ModelContext(container).fetch(FetchDescriptor<ConnectionEntity>())
        #expect(afterBackfill.first?.historyBackfillComplete == true)

        await http.reset()
        _ = try await sync.syncNow()

        let incrementalStart = await http.earliestRequestedStart()
        let expected = Calendar.current.date(
            byAdding: .day,
            value: -SyncCoordinator.incrementalLookbackDays,
            to: .now
        )!
        #expect(incrementalStart != nil)
        #expect(abs(incrementalStart!.timeIntervalSince(expected)) < 172_800)
    }

    @Test("resetLocalDataKeepingLink clears historyBackfillComplete")
    func resetClearsBackfillFlag() async throws {
        let accessStore = InMemoryAccessURLStore()
        try accessStore.save("https://user:pass@example.com/simplefin")
        let http = RecordingAccountsHTTPClient()
        let linking = CompositeBankLinkingService(
            demo: DemoBankLinkingService(),
            simpleFIN: SimpleFINBankLinkingService(
                client: SimpleFINClient(http: http),
                accessURLStore: accessStore
            ),
            initialMode: .simpleFIN
        )
        let container = try ModelContainerFactory.make(inMemory: true)
        let sync = SyncCoordinator(modelContainer: container, bankLinking: linking)
        let lifecycle = ConnectionLifecycleService(
            bankLinking: linking,
            sync: sync,
            resetter: LocalDataResetter(modelContainer: container)
        )

        _ = try await sync.syncNow()
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<ConnectionEntity>())
                .first?.historyBackfillComplete == true
        )

        _ = try await lifecycle.resetLocalDataKeepingLink()
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<ConnectionEntity>())
                .first?.historyBackfillComplete == false
        )
    }
}

// MARK: - Stubs

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

private actor RecordingAccountsHTTPClient: HTTPClient {
    private var startDates: [Date] = []

    func earliestRequestedStart() -> Date? {
        startDates.min()
    }

    func reset() {
        startDates.removeAll()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://example.com")!
        let path = url.path

        if path.contains("info") {
            let data = Data("""
            {"versions":["1","2"]}
            """.utf8)
            return (
                data,
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        if path.contains("accounts") {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let raw = items.first(where: { $0.name == "start-date" })?.value,
               let epoch = TimeInterval(raw)
            {
                startDates.append(Date(timeIntervalSince1970: epoch))
            }
            let end = items.first(where: { $0.name == "end-date" })?.value ?? "0"
            let json = """
            {"errors":[],"errlist":[],"accounts":[{"id":"sf-checking","name":"Checking","currency":"USD","balance":"10.00","balance-date":\(end),"org":{"name":"Real Bank"},"transactions":[]}]}
            """
            return (
                Data(json.utf8),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        return (
            Data(),
            HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        )
    }
}
