import SwiftUI
import CashFlowKit

struct AssistantView: View {
    @Bindable var viewModel: AssistantViewModel
    @Environment(\.dismiss) private var dismiss
    /// Local draft keeps keyboard off the Observable invalidation path.
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    private var showsVoicePrompt: Bool {
        viewModel.canChat
            && viewModel.messages.isEmpty
            && viewModel.pendingProposal == nil
            && !viewModel.isSending
            && !viewModel.isShowingLiveProgress
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.canChat {
                ContentUnavailableView(
                    "Assistant unavailable",
                    systemImage: "sparkles",
                    description: Text(viewModel.availabilityMessage)
                )
            } else {
                chatBody
            }
        }
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            if viewModel.canChat {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        Task { await viewModel.resetConversation() }
                    }
                    .disabled(
                        viewModel.messages.isEmpty
                            && viewModel.pendingProposal == nil
                    )
                }
            }
        }
        .task(priority: .background) {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await viewModel.onAppear()
        }
    }

    private var chatBody: some View {
        VStack(spacing: 0) {
            Text(viewModel.bannerMessage ?? viewModel.availabilityMessage)
                .font(.footnote)
                .foregroundStyle(viewModel.bannerMessage == nil ? Color.secondary : Color.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                AssistantMessageBubble(message: message)
                                    .id(message.id)
                            }
                            if viewModel.isShowingLiveProgress {
                                AssistantLiveProgressBubble(viewModel: viewModel)
                                    .id("assistant.live")
                            }
                            if let proposal = viewModel.pendingProposal {
                                AssistantProposalCard(viewModel: viewModel, proposal: proposal)
                                    .id(proposal.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.pendingProposal?.id) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.liveProgressGeneration) { _, _ in
                        scrollToBottom(proxy)
                    }
                }

                if showsVoicePrompt {
                    voicePromptButton
                }
            }

            AssistantComposerBar(
                viewModel: viewModel,
                draft: $draft,
                isComposerFocused: $isComposerFocused
            )
        }
    }

    private var voicePromptButton: some View {
        Button {
            isComposerFocused = true
            KeyboardDictationStarter.start()
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Color.accentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dictate with keyboard")
        .accessibilityHint("Opens the keyboard and starts voice dictation")
        .accessibilityIdentifier("assistant.dictate")
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let proposal = viewModel.pendingProposal {
            withAnimation { proxy.scrollTo(proposal.id, anchor: .bottom) }
        } else if viewModel.isShowingLiveProgress {
            withAnimation { proxy.scrollTo("assistant.live", anchor: .bottom) }
        } else if let last = viewModel.messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}
