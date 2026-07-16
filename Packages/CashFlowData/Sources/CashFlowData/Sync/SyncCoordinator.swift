import Foundation
import Network
import SwiftData
import os
import CashFlowKit

public actor SyncCoordinator: SyncServing {
    private let modelContainer: ModelContainer
    private let bankLinking: any BankLinkingServing
    private let accessURLStore: any AccessURLStoring
    private let snapshotStore: NetSnapshotStore
    private let logger = Logger(subsystem: "com.expensetracking", category: "sync")

    private var inFlight: Task<LinkedConnection, Error>?
    private var lastSyncStartedAt: Date?
    private let minimumAutomaticInterval: TimeInterval = 60

    public init(
        modelContainer: ModelContainer,
        bankLinking: any BankLinkingServing,
        accessURLStore: any AccessURLStoring = KeychainAccessURLStore(),
        snapshotStore: NetSnapshotStore = NetSnapshotStore()
    ) {
        self.modelContainer = modelContainer
        self.bankLinking = bankLinking
        self.accessURLStore = accessURLStore
        self.snapshotStore = snapshotStore
    }

    public func connectionStatus() async -> LinkedConnection {
        await bankLinking.connectionStatus()
    }

    public func syncNow() async throws -> LinkedConnection {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await performSync() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    public func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    private func performSync() async throws -> LinkedConnection {
        try Task.checkCancellation()
        lastSyncStartedAt = .now

        let startDate: Date?
        let context = ModelContext(modelContainer)
        if let connection = try fetchConnection(context: context),
           let watermark = connection.lastSuccessfulSyncAt
        {
            // Overlap window of 2 days
            startDate = Calendar.current.date(byAdding: .day, value: -2, to: watermark)
        } else {
            startDate = Calendar.current.date(byAdding: .year, value: -2, to: .now)
        }

        do {
            let payload = try await bankLinking.fetchAccounts(
                startDate: startDate,
                endDate: nil
            )
            try Task.checkCancellation()
            try SyncMergeEngine.merge(payload: payload, into: context)

            let connection = try upsertConnection(
                context: context,
                providerName: bankLinking.providerName,
                needsReauth: false,
                syncedAt: .now
            )
            try context.save()
            try writeNetSnapshot(context: context)

            var status = await bankLinking.connectionStatus()
            status = LinkedConnection(
                isLinked: status.isLinked,
                providerName: status.providerName,
                needsReauth: false,
                lastSuccessfulSyncAt: connection.lastSuccessfulSyncAt,
                providerMessages: payload.providerMessages.map(Self.sanitize)
            )
            return status
        } catch let error as CashFlowError {
            if case .unauthorized = error {
                _ = try? upsertConnection(
                    context: context,
                    providerName: bankLinking.providerName,
                    needsReauth: true,
                    syncedAt: nil
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
        syncedAt: Date?
    ) throws -> ConnectionEntity {
        if let existing = try fetchConnection(context: context) {
            existing.providerName = providerName
            existing.needsReauth = needsReauth
            if let syncedAt {
                existing.lastSuccessfulSyncAt = syncedAt
            }
            return existing
        }
        let entity = ConnectionEntity(
            providerName: providerName,
            needsReauth: needsReauth,
            lastSuccessfulSyncAt: syncedAt,
            isDemo: providerName == "Demo"
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
