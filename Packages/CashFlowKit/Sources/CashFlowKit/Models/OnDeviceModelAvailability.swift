import Foundation

/// Domain mirror of Apple Intelligence / Foundation Models readiness.
public enum OnDeviceModelAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceOff
    case modelNotReady
    case unavailable
}
