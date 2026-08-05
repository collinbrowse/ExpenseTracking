import Foundation

/// Extracts structured assistant intent from natural language (no transaction rows).
public protocol TransactionIntentInterpreting: Sendable {
    /// Streams draft updates, then exactly one `.intent` on success.
    func interpret(
        prompt: String,
        accounts: [Account],
        tags: [Tag]
    ) -> AsyncThrowingStream<AssistantIntentStreamEvent, Error>
}
