import Foundation
import CashFlowKit
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct AppleIntelligenceAvailabilityChecker: OnDeviceModelAvailabilityChecking, Sendable {
    /// Avoid re-probing SystemLanguageModel on every foreground activation.
    private static let cacheTTL: TimeInterval = 60

    private struct CacheState: Sendable {
        var value: OnDeviceModelAvailability?
        var expiresAt: Date = .distantPast
    }

    private let cache = OSAllocatedUnfairLock(initialState: CacheState())
    private let workCoordinator: FoundationModelsWorkCoordinator

    public init(workCoordinator: FoundationModelsWorkCoordinator) {
        self.workCoordinator = workCoordinator
    }

    public func availability() async -> OnDeviceModelAvailability {
        if await workCoordinator.isAssetsUnavailable {
            return .modelNotReady
        }

        if let cached = cache.withLock({ state -> OnDeviceModelAvailability? in
            guard let value = state.value, Date() < state.expiresAt else { return nil }
            return value
        }) {
            return cached
        }

        // Never touch SystemLanguageModel on the caller's actor (often MainActor);
        // first access can stall UI / keyboard presentation.
        let value = await Task.detached(priority: .utility) {
            Self.checkAvailability()
        }.value

        cache.withLock { state in
            state.value = value
            state.expiresAt = Date().addingTimeInterval(Self.cacheTTL)
        }
        return value
    }

    nonisolated private static func checkAvailability() -> OnDeviceModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            // Prefer the permissive content-transform model used by enrichment so we
            // don't poke the default safety catalog just to read readiness.
            let model = FoundationModelsWorkCoordinator.contentTransformationModel()
            switch model.availability {
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
