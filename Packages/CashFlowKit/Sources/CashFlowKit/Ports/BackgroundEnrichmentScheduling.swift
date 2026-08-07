import Foundation

/// Schedules user-initiated full enrichment drains and unattended daily continuation.
public protocol BackgroundEnrichmentScheduling: Sendable {
    /// Register launch handlers. Call before app launch finishes for processing tasks.
    func registerHandlers()

    /// Runs a full-history title cleanup now. Call only in response to a user tap.
    /// Publishes live progress via `enrichmentProgressUpdates()` and mirrors it to the
    /// system continued-processing Live Activity when the user leaves the app.
    @discardableResult
    func runFullEnrichmentDrain(
        expectedTotal: Int,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> EnrichmentDrainOutcome

    /// Schedule opportunistic overnight continuation (`BGProcessingTask`).
    func scheduleUnattendedContinuation()

    /// Schedule a sooner retry after Apple Intelligence rate-limits a drain.
    func scheduleUnattendedContinuationSoon()

    /// Track app foreground state so on-device model pacing can slow while backgrounded.
    /// Pacing stays conservative while a background task is draining, regardless of this.
    func setAppForeground(_ isForeground: Bool) async

    /// Whether a full drain is currently running.
    var isFullDrainRunning: Bool { get async }

    /// Live cleanup progress for Settings / tab badge. Yields `nil` when idle.
    func enrichmentProgressUpdates() -> AsyncStream<EnrichmentProgress?>
}

extension BackgroundEnrichmentScheduling {
    @discardableResult
    public func runFullEnrichmentDrain(expectedTotal: Int = 0) async -> EnrichmentDrainOutcome {
        await runFullEnrichmentDrain(expectedTotal: expectedTotal, onProgress: nil)
    }

    public func scheduleUnattendedContinuationSoon() {
        scheduleUnattendedContinuation()
    }

    public func setAppForeground(_ isForeground: Bool) async {
        _ = isForeground
    }

    public func enrichmentProgressUpdates() -> AsyncStream<EnrichmentProgress?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }
}

/// Work estimate shown after a large first sync before starting enrichment.
public struct EnrichmentWorkEstimate: Equatable, Sendable {
    public let untitledCount: Int
    public let distinctMerchantLookups: Int
    public let undefinedCount: Int

    public init(
        untitledCount: Int,
        distinctMerchantLookups: Int,
        undefinedCount: Int = 0
    ) {
        self.untitledCount = untitledCount
        self.distinctMerchantLookups = distinctMerchantLookups
        self.undefinedCount = undefinedCount
    }

    public static let promptThreshold = 50

    public var backlogCount: Int { untitledCount + undefinedCount }

    public var shouldPrompt: Bool { backlogCount > Self.promptThreshold }
}
