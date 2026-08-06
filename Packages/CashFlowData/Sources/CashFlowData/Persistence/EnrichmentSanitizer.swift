import Foundation
import SwiftData
import CashFlowKit

/// One-time store cleanup: drop leaked LLM titles and discard pre-migration rule undo snapshots.
public enum EnrichmentSanitizer {
    private static let defaultsKey = "cashflow.enrichmentSanitizer.v1"

    /// Detached so the one-time full-table scan never blocks app launch. The pass is
    /// idempotent and gated on `defaultsKey`, so a launch that ends before it finishes
    /// simply repeats it next time.
    public static func runIfNeeded(modelContainer: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        Task.detached(priority: .utility) {
            do {
                try run(modelContainer: modelContainer)
                UserDefaults.standard.set(true, forKey: defaultsKey)
            } catch {
                // Best-effort; retry next launch if save failed.
            }
        }
    }

    /// Test entry point that always runs.
    public static func run(modelContainer: ModelContainer) throws {
        let context = ModelContext(modelContainer)
        // Only rows that actually carry enrichment can be stale; the predicate keeps a
        // multi-year store from being faulted in wholesale.
        let transactions = try context.fetch(
            FetchDescriptor<TransactionEntity>(
                predicate: #Predicate { $0.enrichedTitle != nil }
            )
        )
        for entity in transactions {
            if entity.titleSourceRaw == TitleSource.skipped.rawValue {
                continue
            }
            guard let title = entity.enrichedTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty
            else { continue }

            let validated = ValidateParsedDescriptionUseCase.execute(
                title: title,
                location: entity.enrichedLocation,
                rawDescription: entity.transactionDescription
            )
            if let validated {
                entity.enrichedTitle = validated.title
                entity.enrichedLocation = validated.location
                if entity.titleSourceRaw == nil {
                    entity.titleSourceRaw = TitleSource.llm.rawValue
                }
            } else {
                entity.enrichedTitle = nil
                entity.enrichedLocation = nil
                entity.titleSourceRaw = nil
            }
        }

        let rules = try context.fetch(FetchDescriptor<CategorizationRuleEntity>())
        for rule in rules {
            rule.applySnapshotData = nil
        }

        // Seed history watermark from legacy flag when present.
        let connections = try context.fetch(FetchDescriptor<ConnectionEntity>())
        for connection in connections where connection.historyBackfillComplete {
            connection.historyComplete = true
            if connection.earliestFetchedDate == nil {
                let anchor = connection.lastSuccessfulSyncAt ?? .now
                connection.earliestFetchedDate = Calendar.current.date(
                    byAdding: .year,
                    value: -2,
                    to: anchor
                )
            }
        }

        try context.save()
    }
}
