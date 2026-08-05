import Foundation

/// Post-sync enrichment of merchant/location cache and optional LLM categories.
public protocol TransactionEnrichmentRunning: Sendable {
    func enrichAfterSync() async
}
