import Foundation
import CashFlowKit

/// Always-on fallback using bank description heuristics (no LLM).
public struct HeuristicTransactionDescriptionEnricher: TransactionDescriptionEnriching {
    public init() {}

    public func enrich(rawDescription: String) async -> ParsedTransactionDescription {
        ParseTransactionDescriptionUseCase.execute(rawDescription)
    }
}
