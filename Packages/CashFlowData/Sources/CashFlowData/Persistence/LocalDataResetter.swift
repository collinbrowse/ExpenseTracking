import Foundation
import SwiftData
import CashFlowKit

public actor LocalDataResetter {
    private let modelContainer: ModelContainer
    private let snapshotStore: NetSnapshotStore

    public init(
        modelContainer: ModelContainer,
        snapshotStore: NetSnapshotStore = NetSnapshotStore()
    ) {
        self.modelContainer = modelContainer
        self.snapshotStore = snapshotStore
    }

    public func resetAll() async throws {
        let context = ModelContext(modelContainer)
        do {
            // Delete via account cascade — batch-deleting TransactionEntity alone trips
            // the mandatory inverse on TransactionEntity.account.
            // Categorization rules are intentionally kept (user prefs across clear-local / relink).
            let accounts = try context.fetch(FetchDescriptor<AccountEntity>())
            for account in accounts {
                context.delete(account)
            }
            let connections = try context.fetch(FetchDescriptor<ConnectionEntity>())
            for connection in connections {
                context.delete(connection)
            }
            // Orphan transactions (if any) after relationship faults.
            let orphans = try context.fetch(FetchDescriptor<TransactionEntity>())
            for transaction in orphans {
                context.delete(transaction)
            }
            try context.save()
            try? snapshotStore.clear()
        } catch let error as CashFlowError {
            throw error
        } catch {
            throw CashFlowError.persistence(
                message: "Couldn't clear local store. \(error.localizedDescription)"
            )
        }
    }

    /// Removes user categorization rules. Call only from erase-everything.
    public func deleteAllCategorizationRules() async throws {
        let context = ModelContext(modelContainer)
        do {
            let rules = try context.fetch(FetchDescriptor<CategorizationRuleEntity>())
            for rule in rules {
                context.delete(rule)
            }
            try context.save()
        } catch let error as CashFlowError {
            throw error
        } catch {
            throw CashFlowError.persistence(
                message: "Couldn't clear categorization rules. \(error.localizedDescription)"
            )
        }
    }

    /// Clears link/sync metadata while leaving accounts and transactions in place.
    public func clearConnection() async throws {
        let context = ModelContext(modelContainer)
        do {
            try context.delete(model: ConnectionEntity.self)
            try context.save()
        } catch let error as CashFlowError {
            throw error
        } catch {
            throw CashFlowError.persistence(
                message: "Couldn't clear connection metadata. \(error.localizedDescription)"
            )
        }
    }

    /// Writes durable link metadata without a sync watermark (used after reset-keep-link).
    public func upsertConnectionPlaceholder(providerName: String, isDemo: Bool) async throws {
        let context = ModelContext(modelContainer)
        do {
            let predicate = #Predicate<ConnectionEntity> { $0.id == "primary" }
            var descriptor = FetchDescriptor<ConnectionEntity>(predicate: predicate)
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.providerName = providerName
                existing.isDemo = isDemo
                existing.needsReauth = false
                existing.lastSuccessfulSyncAt = nil
                existing.historyBackfillComplete = false
            } else {
                context.insert(
                    ConnectionEntity(
                        providerName: providerName,
                        needsReauth: false,
                        lastSuccessfulSyncAt: nil,
                        isDemo: isDemo,
                        historyBackfillComplete: false
                    )
                )
            }
            try context.save()
        } catch let error as CashFlowError {
            throw error
        } catch {
            throw CashFlowError.persistence(
                message: "Couldn't update connection metadata. \(error.localizedDescription)"
            )
        }
    }
}
