import Foundation

/// Result of a full title-cleanup drain for Settings / scheduling.
public enum EnrichmentDrainOutcome: Equatable, Sendable {
    /// Walked the backlog to completion (including permanently unparseable rows).
    case completed
    /// Stopped early because Apple Intelligence is cooling down.
    case interruptedByRateLimit
    /// Stopped early for another reason (cancel, assets, assistant priority).
    case interrupted

    public var shouldAutoResume: Bool {
        switch self {
        case .interruptedByRateLimit: return true
        case .completed, .interrupted: return false
        }
    }

    public var wasRateLimited: Bool {
        if case .interruptedByRateLimit = self { return true }
        return false
    }
}
