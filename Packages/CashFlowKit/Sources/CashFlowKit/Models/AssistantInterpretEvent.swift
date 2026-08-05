import Foundation

/// Progress while the assistant interprets a prompt into a proposal.
public enum AssistantInterpretEvent: Equatable, Sendable {
    case status(String)
    case draft(explanation: String, conditionSummary: String)
    case proposal(AssistantProposal)
}

/// Partial or final structured intent while the on-device model streams.
public enum AssistantIntentStreamEvent: Equatable, Sendable {
    case draft(explanation: String, conditionSummary: String)
    case intent(AssistantIntent)
}
