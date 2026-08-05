import Foundation

/// Post-sync enrichment of merchant/location cache and optional LLM categories.
public protocol TransactionEnrichmentRunning: Sendable {
    /// - Parameter onProgress: `completed` / `total` enrichment units when work runs.
    func enrichAfterSync(
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async
}

extension TransactionEnrichmentRunning {
    public func enrichAfterSync() async {
        await enrichAfterSync(onProgress: nil)
    }
}
