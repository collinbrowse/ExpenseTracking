import SwiftUI

struct SimpleFINLinkSheet: View {
    @Bindable var viewModel: AccountsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Create a token at SimpleFIN Bridge, then paste it here."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Button("Open SimpleFIN Bridge") {
                        viewModel.openSimpleFINCreate()
                    }
                    .disabled(viewModel.isWorking)
                    TextField("Setup token", text: $viewModel.setupToken, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(viewModel.isWorking)
                        .accessibilityIdentifier("accounts.token")
                } footer: {
                    if viewModel.isWorking, let title = viewModel.workingTitle {
                        Text(title)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Link SimpleFIN")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showLinkSheet = false }
                        .disabled(viewModel.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        Task { await viewModel.linkSimpleFIN() }
                    }
                    .disabled(
                        viewModel.isWorking
                            || viewModel.setupToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .interactiveDismissDisabled(viewModel.isWorking)
            .overlay {
                if viewModel.isWorking {
                    AccountsBusyOverlay(title: viewModel.workingTitle ?? "Linking…")
                }
            }
        }
    }
}
