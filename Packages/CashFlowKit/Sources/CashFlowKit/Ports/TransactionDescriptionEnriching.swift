import Foundation

/// Resolves a clean merchant title and optional location from a bank description.
/// Implementations may use on-device LLM enrichment or heuristics; always returns a result.
public protocol TransactionDescriptionEnriching: Sendable {
    func enrich(rawDescription: String) async -> ParsedTransactionDescription
}
