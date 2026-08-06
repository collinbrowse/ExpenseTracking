import Foundation

/// Post-sync enrichment of merchant/location cache and optional LLM categories.
public protocol TransactionEnrichmentRunning: Sendable {
    /// Incremental bounded drain after sync / foreground. Skips when a full drain is running
    /// or when `skipIfLargeBacklog` and the untitled count exceeds the prompt threshold.
    func enrichAfterSync(
        skipIfLargeBacklog: Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> EnrichmentWorkEstimate?

    /// Full unbounded drain of the untitled backlog. Used by user-initiated background work.
    @discardableResult
    func drainAllNeedingEnrichment(
        shouldContinue: @escaping @Sendable () -> Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> EnrichmentDrainOutcome

    /// Full drain with phase callbacks (running vs cooling down for rate limits).
    @discardableResult
    func drainAllNeedingEnrichment(
        shouldContinue: @escaping @Sendable () -> Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?,
        onPhase: (@Sendable (_ phase: EnrichmentProgress.Phase, _ detail: String?) -> Void)?
    ) async -> EnrichmentDrainOutcome

    /// Whether a full drain is currently in flight.
    var isFullDrainRunning: Bool { get async }
}

extension TransactionEnrichmentRunning {
    public func enrichAfterSync() async -> EnrichmentWorkEstimate? {
        await enrichAfterSync(skipIfLargeBacklog: false, onProgress: nil)
    }

    public func enrichAfterSync(
        skipIfLargeBacklog: Bool
    ) async -> EnrichmentWorkEstimate? {
        await enrichAfterSync(skipIfLargeBacklog: skipIfLargeBacklog, onProgress: nil)
    }

    public func enrichAfterSync(
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> EnrichmentWorkEstimate? {
        await enrichAfterSync(skipIfLargeBacklog: false, onProgress: onProgress)
    }

    @discardableResult
    public func drainAllNeedingEnrichment(
        shouldContinue: @escaping @Sendable () -> Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?,
        onPhase: (@Sendable (_ phase: EnrichmentProgress.Phase, _ detail: String?) -> Void)?
    ) async -> EnrichmentDrainOutcome {
        _ = onPhase
        return await drainAllNeedingEnrichment(shouldContinue: shouldContinue, onProgress: onProgress)
    }
}
