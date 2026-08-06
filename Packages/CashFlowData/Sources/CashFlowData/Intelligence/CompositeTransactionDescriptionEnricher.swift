import Foundation
import CashFlowKit

/// Tries on-device LLM enrichment when available; otherwise returns an empty title (no heuristic).
public struct CompositeTransactionDescriptionEnricher: TransactionDescriptionEnriching {
    private let availability: any OnDeviceModelAvailabilityChecking
    private let foundation: (any TransactionDescriptionEnriching)?
    private let workCoordinator: FoundationModelsWorkCoordinator

    public init(
        availability: any OnDeviceModelAvailabilityChecking,
        foundation: (any TransactionDescriptionEnriching)?,
        workCoordinator: FoundationModelsWorkCoordinator
    ) {
        self.availability = availability
        self.foundation = foundation
        self.workCoordinator = workCoordinator
    }

    public func enrich(rawDescription: String) async -> ParsedTransactionDescription {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedTransactionDescription(title: "", location: nil, raw: "")
        }
        if await workCoordinator.isAssetsUnavailable {
            return ParsedTransactionDescription(title: "", location: nil, raw: trimmed)
        }
        if await availability.availability() == .available, let foundation {
            let parsed = await foundation.enrich(rawDescription: trimmed)
            if !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return parsed
            }
        }
        return ParsedTransactionDescription(title: "", location: nil, raw: trimmed)
    }
}
