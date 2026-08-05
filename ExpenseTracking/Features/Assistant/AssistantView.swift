import SwiftUI
import UIKit
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
                                messageBubble(message)
                                    .id(message.id)
                            }
                            if viewModel.isShowingLiveProgress {
                                liveProgressBubble
                                    .id("assistant.live")
                            }
                            if let proposal = viewModel.pendingProposal {
                                proposalCard(proposal)
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

            composerBar
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

    private var liveProgressBubble: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            ZStack(alignment: .leading) {
                if let line = viewModel.liveProgressLine {
                    Text(line)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(viewModel.liveProgressGeneration)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }
            }
            .clipped()
            .animation(.snappy(duration: 0.28), value: viewModel.liveProgressGeneration)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("assistant.live")
        .accessibilityLabel(viewModel.liveProgressLine ?? "Working")
    }

    private func proposalCard(_ proposal: AssistantProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(proposal.summary)
                .font(.body.weight(.semibold))
            Text(proposal.conditionSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(proposal.affectedCount) affected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(proposal.isLargeSet ? .orange : .primary)
                if proposal.isLargeSet {
                    Text("Large set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            if !proposal.warnings.isEmpty {
                ForEach(proposal.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !proposal.samples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Examples")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(proposal.samples) { sample in
                        Text("• \(sample.title) — \(sample.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if proposal.appliesCategory || !proposal.tagNames.isEmpty {
                Toggle(
                    "Save Rule",
                    isOn: Binding(
                        get: { viewModel.pendingProposal?.saveAsRule ?? proposal.saveAsRule },
                        set: { viewModel.setSaveAsRule($0) }
                    )
                )
                .font(.subheadline)
            }

            HStack {
                Button("Discard") {
                    viewModel.discardPendingProposal()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isExecuting)

                Spacer()

                Button {
                    Task { await viewModel.executePendingProposal() }
                } label: {
                    if viewModel.isExecuting {
                        ProgressView()
                    } else {
                        Text("Run")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isExecuting || proposal.affectedCount == 0)
                .accessibilityIdentifier("assistant.run")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask to tag or categorize…", text: $draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .focused($isComposerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .accessibilityIdentifier("assistant.draft")

            Button {
                let text = draft
                draft = ""
                Task { await viewModel.send(text) }
            } label: {
                Group {
                    if viewModel.isSending {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48)
                .background(
                    canSend ? Color.accentColor : Color(.tertiarySystemFill),
                    in: Circle()
                )
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("assistant.send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var canSend: Bool {
        !viewModel.isSending
            && !viewModel.isExecuting
            && viewModel.pendingProposal == nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func messageBubble(_ message: AssistantMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleColor(for: message.role), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button("Copy") {
                        UIPasteboard.general.string = message.text
                    }
                }
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private func bubbleColor(for role: AssistantMessage.Role) -> Color {
        switch role {
        case .user: Color.accentColor.opacity(0.18)
        case .assistant: Color(.secondarySystemBackground)
        case .system: Color(.tertiarySystemBackground)
        }
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
