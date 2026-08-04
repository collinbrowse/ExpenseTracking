import SwiftUI

struct AppLockGateView: View {
    let biometryDisplayName: String
    let showUnlockControls: Bool
    let isAuthenticating: Bool
    let errorMessage: String?
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Cash Flow")
                    .font(.title2.weight(.semibold))

                if showUnlockControls {
                    Text("App Locked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        onUnlock()
                    } label: {
                        if isAuthenticating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Unlock with \(biometryDisplayName)")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAuthenticating)
                    .padding(.horizontal, 32)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App locked")
    }
}
