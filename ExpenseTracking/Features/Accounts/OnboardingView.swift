import SwiftUI
import CashFlowKit

struct OnboardingView: View {
    @Bindable var viewModel: AccountsViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Cash Flow")
                    .font(.largeTitle.bold())
                Text("See whether you've made more than you've spent — for the month, 30 days, or a custom range.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await viewModel.loadDemo() }
                } label: {
                    Text("Explore with Demo Data")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)
                .accessibilityIdentifier("onboarding.demo")

                Button {
                    viewModel.beginLinkFlowFromOnboarding()
                } label: {
                    Text("Link SimpleFIN")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking)
                .accessibilityIdentifier("onboarding.link")

                Button("Skip for now") {
                    viewModel.dismissOnboarding()
                }
                .font(.footnote)
                .disabled(viewModel.isWorking)
            }
            .padding(28)
            .overlay {
                if viewModel.isWorking {
                    AccountsBusyOverlay(title: viewModel.workingTitle ?? "Working…")
                }
            }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
    }
}
