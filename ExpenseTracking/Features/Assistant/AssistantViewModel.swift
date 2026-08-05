import Foundation
import Observation
import CashFlowKit

@MainActor
@Observable
final class AssistantViewModel {
    private let availabilityChecker: any OnDeviceModelAvailabilityChecking
    private let assistant: any TransactionAssistantServing

    /// Optimistic: iOS 26 always has the framework; correct after deferred availability check.
    var availability: OnDeviceModelAvailability = .available
    var messages: [AssistantMessage] = []
    var pendingProposal: AssistantProposal?
    var isSending = false
    var isExecuting = false
    var bannerMessage: String?
    /// Single live progress line; each update replaces the previous (no stacking).
    var liveProgressLine: String?
    /// Bumps on each replace so the view can animate a rollover.
    var liveProgressGeneration = 0

    init(
        availabilityChecker: any OnDeviceModelAvailabilityChecking,
        assistant: any TransactionAssistantServing,
        transactionRepository: any TransactionRepository
    ) {
        self.availabilityChecker = availabilityChecker
        self.assistant = assistant
        // Repository param kept for call-site stability with DependencyContainer wiring.
        _ = transactionRepository
    }

    var canChat: Bool { availability == .available }

    var isShowingLiveProgress: Bool {
        isSending && liveProgressLine != nil
    }

    var availabilityMessage: String {
        switch availability {
        case .available:
            return "On-device Apple Intelligence is ready. Ask to tag or categorize transactions."
        case .deviceNotEligible:
            return "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceOff:
            return "Turn on Apple Intelligence in Settings to use the assistant."
        case .modelNotReady:
            return "Apple Intelligence is downloading or preparing. Try again shortly."
        case .unavailable:
            return "On-device intelligence isn’t available right now."
        }
    }

    /// Called after the sheet is interactive. Avoids contending with keyboard presentation.
    func onAppear() async {
        let nextAvailability = await availabilityChecker.availability()
        if nextAvailability != availability {
            availability = nextAvailability
        }
    }

    func send(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canChat, !isSending, !isExecuting else { return }
        bannerMessage = nil
        pendingProposal = nil
        clearLiveProgress()
        messages.append(AssistantMessage(role: .user, text: text))
        isSending = true
        replaceLiveProgress("Understanding your request…")
        defer {
            isSending = false
            clearLiveProgress()
        }

        do {
            for try await event in assistant.interpret(prompt: text) {
                switch event {
                case .status(let status):
                    replaceLiveProgress(status)
                case .draft(let explanation, let conditionSummary):
                    if !explanation.isEmpty {
                        replaceLiveProgress(explanation)
                    } else if !conditionSummary.isEmpty {
                        replaceLiveProgress(conditionSummary)
                    }
                case .proposal(let proposal):
                    // Proposal card is the only preview UI — no duplicate chat bubble.
                    pendingProposal = proposal
                    clearLiveProgress()
                }
            }
        } catch {
            clearLiveProgress()
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "On-device generation failed. Try again with a shorter request."
            )
        }
    }

    func setSaveAsRule(_ enabled: Bool) {
        guard var proposal = pendingProposal else { return }
        let canSave = proposal.appliesCategory || !proposal.tagNames.isEmpty
        proposal.saveAsRule = enabled && canSave
        pendingProposal = proposal
    }

    func executePendingProposal() async {
        guard let proposal = pendingProposal, !isExecuting, !isSending else { return }
        isExecuting = true
        defer { isExecuting = false }
        bannerMessage = nil
        do {
            let turn = try await assistant.execute(proposal)
            pendingProposal = nil
            messages.append(turn.message)
        } catch {
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't apply that change."
            )
        }
    }

    func discardPendingProposal() {
        pendingProposal = nil
        messages.append(AssistantMessage(role: .system, text: "Discarded the proposal."))
    }

    func resetConversation() async {
        await assistant.reset()
        messages = []
        pendingProposal = nil
        bannerMessage = nil
        clearLiveProgress()
    }

    private func replaceLiveProgress(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != liveProgressLine else { return }
        liveProgressLine = trimmed
        liveProgressGeneration += 1
    }

    private func clearLiveProgress() {
        liveProgressLine = nil
    }
}
