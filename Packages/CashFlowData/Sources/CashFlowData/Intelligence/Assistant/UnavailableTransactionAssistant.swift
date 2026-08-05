import Foundation
import CashFlowKit

/// Fallback when Foundation Models is not available on this OS/SDK.
public actor UnavailableTransactionAssistant: TransactionAssistantServing {
    public init() {}

    public func reset() async {}

    public nonisolated func interpret(
        prompt: String
    ) -> AsyncThrowingStream<AssistantInterpretEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CashFlowError.intelligenceUnavailable)
        }
    }

    public func execute(_ proposal: AssistantProposal) async throws -> AssistantTurn {
        throw CashFlowError.intelligenceUnavailable
    }

    public func undoLastChange() async throws {
        throw CashFlowError.intelligenceUnavailable
    }

    public func lastUndoSnapshot() async -> AssistantUndoSnapshot? { nil }

    public func discardUndoSnapshot() async {}
}
