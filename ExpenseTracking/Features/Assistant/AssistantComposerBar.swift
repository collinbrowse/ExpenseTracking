import SwiftUI

struct AssistantComposerBar: View {
    @Bindable var viewModel: AssistantViewModel
    @Binding var draft: String
    var isComposerFocused: FocusState<Bool>.Binding

    private var canSend: Bool {
        !viewModel.isSending
            && !viewModel.isExecuting
            && viewModel.pendingProposal == nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask to tag or categorize…", text: $draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .focused(isComposerFocused)
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
}
