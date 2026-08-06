import Foundation

/// Honest sync progress: stages and known work units (date windows / enrichment items).
/// Transaction totals are never available from SimpleFIN up front.
public struct SyncProgress: Sendable, Equatable {
    public enum Phase: String, Sendable, Equatable {
        case preparing
        case downloading
        case saving
        case backfillingHistory
        case enriching
    }

    public let phase: Phase
    /// Completed units in this phase (windows or enrichment items).
    public let completedUnits: Int
    /// Total units when known; `nil` means indeterminate (preparing / saving).
    public let totalUnits: Int?

    public init(phase: Phase, completedUnits: Int = 0, totalUnits: Int? = nil) {
        self.phase = phase
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
    }

    public var fractionCompleted: Double? {
        guard let totalUnits, totalUnits > 0 else { return nil }
        return min(1, Double(completedUnits) / Double(totalUnits))
    }
}
