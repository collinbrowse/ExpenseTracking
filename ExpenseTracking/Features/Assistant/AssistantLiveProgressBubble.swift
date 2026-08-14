import SwiftUI

struct AssistantLiveProgressBubble: View {
    @Bindable var viewModel: AssistantViewModel

    var body: some View {
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
}
