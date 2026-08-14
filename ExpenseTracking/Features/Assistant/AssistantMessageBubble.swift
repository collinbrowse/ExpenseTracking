import SwiftUI
import UIKit
import CashFlowKit

struct AssistantMessageBubble: View {
    let message: AssistantMessage

    var body: some View {
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
}
