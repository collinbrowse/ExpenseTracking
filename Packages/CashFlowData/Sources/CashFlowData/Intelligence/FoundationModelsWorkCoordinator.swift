import Foundation
import CashFlowKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Serializes on-device model work so enrichment and the assistant never contend,
/// even across `await` suspension points (Swift actors are reentrant).
public actor FoundationModelsWorkCoordinator {
    public static let shared = FoundationModelsWorkCoordinator()

    private var assistantPriorityCount = 0
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func beginAssistantPriority() {
        assistantPriorityCount += 1
    }

    public func endAssistantPriority() {
        assistantPriorityCount = max(0, assistantPriorityCount - 1)
    }

    public var isAssistantPriorityActive: Bool {
        assistantPriorityCount > 0
    }

    /// Runs a single generation unit with a non-reentrant mutex.
    public func runExclusive<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async throws -> T {
        while isBusy {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        isBusy = true
        defer {
            isBusy = false
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            }
        }
        return try await work()
    }

    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    public static func contentTransformationModel() -> SystemLanguageModel {
        SystemLanguageModel(guardrails: .permissiveContentTransformations)
    }

    /// Maps Foundation Models errors into user-facing copy. Always prefer throwing
    /// `CashFlowError.intelligence(message:)` at the port boundary afterward.
    @available(iOS 26, macOS 26, *)
    public static func userFacingMessage(for error: Error) -> String {
        if CashFlowError.fromBridgedError(error) != nil {
            return CashFlowError.userFacingMessage(
                for: error,
                fallback: "On-device generation failed."
            )
        }
        if let generation = error as? LanguageModelSession.GenerationError {
            if let recovery = generation.recoverySuggestion, !recovery.isEmpty {
                return recovery
            }
            if let reason = generation.failureReason, !reason.isEmpty {
                return reason
            }
            if let description = generation.errorDescription, !description.isEmpty {
                return description
            }
            switch generation {
            case .exceededContextWindowSize:
                return "The conversation got too long. Tap Reset and try again."
            case .assetsUnavailable:
                return "Apple Intelligence assets aren’t ready. Try again in a moment."
            case .guardrailViolation:
                return "Apple Intelligence couldn’t process that request. Try rephrasing."
            case .unsupportedGuide:
                return "On-device generation hit an unsupported constraint."
            case .unsupportedLanguageOrLocale:
                return "That language isn’t supported by Apple Intelligence on this device."
            case .decodingFailure:
                return "The model returned an unexpected shape. Try again."
            case .rateLimited:
                return "Apple Intelligence is busy. Wait a moment and try again."
            case .concurrentRequests:
                return "Another on-device request is still running. Try again."
            case .refusal:
                return "The model declined that request. Try a more specific prompt."
            @unknown default:
                return "On-device generation failed. Try again."
            }
        }
        if let toolError = error as? LanguageModelSession.ToolCallError {
            return userFacingMessage(for: toolError.underlyingError)
        }
        return CashFlowError.userFacingMessage(
            for: error,
            fallback: "On-device generation failed. Try Reset, then ask again with a shorter request."
        )
    }
    #endif
}
