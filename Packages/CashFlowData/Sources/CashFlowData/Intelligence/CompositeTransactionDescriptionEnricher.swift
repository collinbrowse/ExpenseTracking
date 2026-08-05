import Foundation
import CashFlowKit

/// Tries on-device LLM enrichment when available; otherwise heuristic parse.
public struct CompositeTransactionDescriptionEnricher: TransactionDescriptionEnriching {
    private let availability: any OnDeviceModelAvailabilityChecking
    private let foundation: (any TransactionDescriptionEnriching)?
    private let heuristic: any TransactionDescriptionEnriching

    public init(
        availability: any OnDeviceModelAvailabilityChecking,
        foundation: (any TransactionDescriptionEnriching)?,
        heuristic: any TransactionDescriptionEnriching = HeuristicTransactionDescriptionEnricher()
    ) {
        self.availability = availability
        self.foundation = foundation
        self.heuristic = heuristic
    }

    public func enrich(rawDescription: String) async -> ParsedTransactionDescription {
        if await availability.availability() == .available, let foundation {
            let parsed = await foundation.enrich(rawDescription: rawDescription)
            if !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return parsed
            }
        }
        return await heuristic.enrich(rawDescription: rawDescription)
    }
}
