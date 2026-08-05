import Foundation
import Network
import SwiftData
import os
import CashFlowKit

public actor SyncCoordinator: SyncServing {
    /// After history backfill, re-fetch this many days before the watermark so
    /// pending→posted updates with older `posted` dates still arrive.
    public static let incrementalLookbackDays = 30

    private let modelContainer: ModelContainer
    private let bankLinking: CompositeBankLinkingService
    private let snapshotStore: NetSnapshotStore
    private let enrichment: (any TransactionEnrichmentRunning)?
    nonisolated private let progressHub: SyncProgressHub
    private let logger = Logger(subsystem: "com.expensetracking", category: "sync")

    private var inFlight: Task<LinkedConnection, Error>?

    public init(
        modelContainer: ModelContainer,
        bankLinking: CompositeBankLinkingService,
        snapshotStore: NetSnapshotStore = NetSnapshotStore(),
        enrichment: (any TransactionEnrichmentRunning)? = nil,
        progressHub: SyncProgressHub = SyncProgressHub()
    ) {
        self.modelContainer = modelContainer
        self.bankLinking = bankLinking
        self.snapshotStore = snapshotStore
        self.enrichment = enrichment
        self.progressHub = progressHub
    }

    /// Assembles UI status from credentials (Keychain / Demo session) + durable `ConnectionEntity`.
    public func connectionStatus() async -> LinkedConnection {
        let context = ModelContext(modelContainer)
        let entity = try? fetchConnection(context: context)

        // Durable Demo survives process death via ConnectionEntity.isDemo.
        if entity?.isDemo == true {
            let simpleLinked = await bankLinking.connectionStatus()
            // Prefer SimpleFIN credentials if both somehow exist.
            if simpleLinked.isLinked, simpleLinked.providerName == "SimpleFIN" {
                return LinkedConnection(
                    isLinked: true,
                    providerName: "SimpleFIN",
                    needsReauth: entity?.needsReauth ?? false,
                    lastSuccessfulSyncAt: entity?.lastSuccessfulSyncAt
                )
            }
            await bankLinking.adoptDurableDemoLink()
            return LinkedConnection(
                isLinked: true,
                providerName: "Demo",
                needsReauth: entity?.needsReauth ?? false,
                lastSuccessfulSyncAt: entity?.lastSuccessfulSyncAt
            )
        }

        let credentials = await bankLinking.connectionStatus()
        guard credentials.isLinked else {
            return LinkedConnection(isLinked: false, providerName: "None")
        }

        return LinkedConnection(
            isLinked: true,
            providerName: credentials.providerName,
            needsReauth: entity?.needsReauth ?? credentials.needsReauth,
            lastSuccessfulSyncAt: entity?.lastSuccessfulSyncAt
        )
    }

    nonisolated public func syncProgressUpdates() -> AsyncStream<SyncProgress?> {
        progressHub.subscribe()
    }

    public func syncNow() async throws -> LinkedConnection {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await performSync() }
        inFlight = task
        defer {
            inFlight = nil
            progressHub.emit(nil)
        }
        return try await task.value
    }

    /// Cancels the in-flight sync and waits until the slot is free (no overlapping syncNow).
    public func cancel() async {
        guard let task = inFlight else { return }
        task.cancel()
        _ = await task.result
    }

    private func emit(_ progress: SyncProgress) {
        progressHub.emit(progress)
    }

    private func performSync() async throws -> LinkedConnection {
        try Task.checkCancellation()
        emit(SyncProgress(phase: .preparing))

        // Restore durable Demo / SimpleFIN mode before fetch — in-memory link state
        // is lost on process death and resolveModeIfNeeded cannot see ConnectionEntity.
        _ = await connectionStatus()

        let context = ModelContext(modelContainer)
        let existing = try fetchConnection(context: context)
        let needsHistoryBackfill = existing?.historyBackfillComplete != true
        let startDate: Date?
        if !needsHistoryBackfill, let watermark = existing?.lastSuccessfulSyncAt {
            startDate = Calendar.current.date(
                byAdding: .day,
                value: -Self.incrementalLookbackDays,
                to: watermark
            )
        } else {
            // Full lookback until one successful historical sync completes.
            // Watermark-only syncs must not run before that or older windows are never requested again.
            startDate = Calendar.current.date(byAdding: .year, value: -2, to: .now)
        }

        do {
            let payload = try await bankLinking.fetchAccounts(
                startDate: startDate,
                endDate: nil,
                onWindowProgress: { [progressHub] completed, total in
                    progressHub.emit(
                        SyncProgress(
                            phase: .downloading,
                            completedUnits: completed,
                            totalUnits: total
                        )
                    )
                }
            )
            try Task.checkCancellation()
            emit(SyncProgress(phase: .saving))
            try SyncMergeEngine.merge(payload: payload, into: context)

            let providerName = await bankLinking.activeProviderName()
            let connection = try upsertConnection(
                context: context,
                providerName: providerName,
                needsReauth: false,
                syncedAt: .now,
                isDemo: providerName == "Demo",
                historyBackfillComplete: true
            )
            try context.save()
            try writeNetSnapshot(context: context)

            // Best-effort on-device enrichment; never fails the sync.
            if let enrichment {
                await enrichment.enrichAfterSync { [progressHub] completed, total in
                    progressHub.emit(
                        SyncProgress(
                            phase: .enriching,
                            completedUnits: completed,
                            totalUnits: total
                        )
                    )
                }
            }

            return LinkedConnection(
                isLinked: true,
                providerName: providerName,
                needsReauth: false,
                lastSuccessfulSyncAt: connection.lastSuccessfulSyncAt,
                providerMessages: payload.providerMessages.map(Self.sanitize)
            )
        } catch let error as CashFlowError {
            if case .unauthorized = error {
                let providerName = await bankLinking.activeProviderName()
                _ = try? upsertConnection(
                    context: context,
                    providerName: providerName == "None" ? "SimpleFIN" : providerName,
                    needsReauth: true,
                    syncedAt: nil,
                    isDemo: false,
                    historyBackfillComplete: existing?.historyBackfillComplete ?? false
                )
                try? context.save()
            }
            logger.error("Sync failed: \(String(describing: error), privacy: .public)")
            throw error
        } catch is CancellationError {
            throw CashFlowError.cancelled
        } catch {
            logger.error("Sync transport failure")
            throw CashFlowError.transport(message: error.localizedDescription)
        }
    }

    private func writeNetSnapshot(context: ModelContext) throws {
        let range = CashFlowDateRange.month(.now)
        let interval = range.interval()
        let descriptor = FetchDescriptor<TransactionEntity>()
        let entities = try context.fetch(descriptor)
        let transactions = entities
            .filter { !$0.isPending && $0.postedDate >= interval.start && $0.postedDate <= interval.end }
            .map(EntityMappers.transaction(from:))
        let result = CalculateNetCashFlowUseCase().execute(
            transactions: transactions,
            range: range
        )
        let snapshot = NetCashFlowSnapshot(
            net: result.net,
            incomeTotal: result.incomeTotal,
            expenseTotal: result.expenseTotal,
            rangeLabel: "This Month"
        )
        try? snapshotStore.save(snapshot)
    }

    private func fetchConnection(context: ModelContext) throws -> ConnectionEntity? {
        let predicate = #Predicate<ConnectionEntity> { $0.id == "primary" }
        var descriptor = FetchDescriptor<ConnectionEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    private func upsertConnection(
        context: ModelContext,
        providerName: String,
        needsReauth: Bool,
        syncedAt: Date?,
        isDemo: Bool,
        historyBackfillComplete: Bool
    ) throws -> ConnectionEntity {
        if let existing = try fetchConnection(context: context) {
            existing.providerName = providerName
            existing.needsReauth = needsReauth
            existing.isDemo = isDemo
            existing.historyBackfillComplete = historyBackfillComplete
            if let syncedAt {
                existing.lastSuccessfulSyncAt = syncedAt
            }
            return existing
        }
        let entity = ConnectionEntity(
            providerName: providerName,
            needsReauth: needsReauth,
            lastSuccessfulSyncAt: syncedAt,
            isDemo: isDemo,
            historyBackfillComplete: historyBackfillComplete
        )
        context.insert(entity)
        return entity
    }

    private static func sanitize(_ string: String) -> String {
        string.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
    }
}

public final class ConnectivityMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.expensetracking.connectivity")
    public private(set) var isOnline = true

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = path.status == .satisfied
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
