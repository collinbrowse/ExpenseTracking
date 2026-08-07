import Foundation

/// Resolves a clean merchant title and optional location from a bank description.
/// Product implementations use on-device LLM enrichment; always returns a result
/// (empty title means leave the row on raw bank text).
public protocol TransactionDescriptionEnriching: Sendable {
    func enrich(rawDescription: String) async -> ParsedTransactionDescription
}
