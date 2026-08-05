import Foundation
import CashFlowKit

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct AppleIntelligenceAvailabilityChecker: OnDeviceModelAvailabilityChecking, Sendable {
    public init() {}

    public func availability() async -> OnDeviceModelAvailability {
        // Never touch SystemLanguageModel on the caller's actor (often MainActor);
        // first access can stall UI / keyboard presentation.
        await Task.detached(priority: .utility) {
            Self.checkAvailability()
        }.value
    }

    nonisolated private static func checkAvailability() -> OnDeviceModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceOff
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        }
        #endif
        return .deviceNotEligible
    }
}
