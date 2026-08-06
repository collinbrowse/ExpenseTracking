import Foundation
import SwiftData
import CashFlowKit

/// Returns `TitleSource.skipped` rows to the backlog when the enrichment generation bumps.
///
/// A skip is a judgement by one version of the on-device model on one day: a guardrail
/// refusal, an unsupported locale, a malformed generation. Without this pass that judgement
/// is permanent and the row shows raw bank text forever, with no way for a smarter model or
/// a fixed prompt to reach it. Bump `currentGeneration` whenever parsing or validation
/// changes in a way that could rescue previously unparseable descriptions.
public enum EnrichmentSkipReviver {
    public static let currentGeneration = 1

    private static let defaultsKey = "cashflow.enrichmentSkipGeneration"

    public static func runIfNeeded(modelContainer: ModelContainer) {
        let defaults = UserDefaults.standard
        // Absent key means a store written before skips existed — nothing to revive.
        let stored = defaults.object(forKey: defaultsKey) as? Int
        guard stored != currentGeneration else { return }
        Task.detached(priority: .utility) {
            do {
                try revive(modelContainer: modelContainer)
                UserDefaults.standard.set(currentGeneration, forKey: defaultsKey)
            } catch {
                // Best-effort; retry next launch.
            }
        }
    }

    /// Clears the skip marker so the rows re-enter `fetchNeedingEnrichment`.
    /// Returns the number of rows revived.
    @discardableResult
    public static func revive(modelContainer: ModelContainer) throws -> Int {
        let context = ModelContext(modelContainer)
        let skipped = TitleSource.skipped.rawValue
        let descriptor = FetchDescriptor<TransactionEntity>(
            predicate: #Predicate { $0.titleSourceRaw == skipped }
        )
        let entities = try context.fetch(descriptor)
        guard !entities.isEmpty else { return 0 }
        for entity in entities {
            entity.titleSourceRaw = nil
        }
        try context.save()
        return entities.count
    }
}
