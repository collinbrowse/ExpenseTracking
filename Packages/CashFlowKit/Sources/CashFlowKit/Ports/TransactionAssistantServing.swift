import Foundation

/// Natural-language assistant: interpret → proposal → execute on user confirmation.
public protocol TransactionAssistantServing: Sendable {
    /// Clears any undo snapshot and pending proposal state.
    func reset() async

    /// Interprets a prompt into a preview proposal. Emits status/draft events, then `.proposal`.
    func interpret(prompt: String) -> AsyncThrowingStream<AssistantInterpretEvent, Error>

    /// Applies a proposal the user confirmed. May save a rule and mutate transactions.
    func execute(_ proposal: AssistantProposal) async throws -> AssistantTurn

    /// Restores the last undo snapshot (transactions + disables created/updated rule).
    func undoLastChange() async throws

    /// Latest undo snapshot from an applied turn, if any.
    func lastUndoSnapshot() async -> AssistantUndoSnapshot?

    /// Clears the undo snapshot without restoring data.
    func discardUndoSnapshot() async
}
