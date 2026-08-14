import SwiftUI
import CashFlowKit

struct AccountsBusyOverlay: View {
    let title: String
    var progress: SyncProgress? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                if let progress, let fraction = progress.fractionCompleted {
                    ProgressView(value: fraction)
                        .frame(width: 160)
                } else {
                    ProgressView()
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("accounts.busy")
        .accessibilityLabel(title)
    }
}
