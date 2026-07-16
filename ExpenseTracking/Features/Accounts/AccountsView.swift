import SwiftUI

struct AccountsView: View {
    @Bindable var viewModel: AccountsViewModel

    var body: some View {
        List {
            if let message = viewModel.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Connection") {
                LabeledContent("Provider", value: viewModel.connection.providerName)
                LabeledContent(
                    "Status",
                    value: viewModel.connection.isLinked
                        ? (viewModel.connection.needsReauth ? "Reconnect required" : "Linked")
                        : "Not linked"
                )
                if let synced = viewModel.connection.lastSuccessfulSyncAt {
                    LabeledContent("Last sync", value: DateFormatting.medium(synced))
                }

                Button("Sync Now") {
                    Task { await viewModel.syncNow() }
                }
                .disabled(viewModel.isWorking || !viewModel.connection.isLinked)
                .accessibilityIdentifier("accounts.sync")

                Button("Link SimpleFIN…") {
                    viewModel.showLinkSheet = true
                }
                .accessibilityIdentifier("accounts.link")

                Button("Load Demo Data") {
                    Task { await viewModel.loadDemo() }
                }
                .accessibilityIdentifier("accounts.demo")
            }

            Section("Accounts") {
                if viewModel.accounts.isEmpty {
                    Text("No accounts yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.accounts) { account in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                            Text("\(account.institutionName) · \(CurrencyFormatting.usd(account.balance))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Manage") {
                Button("Disconnect (keep local data)", role: .destructive) {
                    Task { await viewModel.disconnect(removeLocalData: false) }
                }
                Button("Disconnect & delete local data", role: .destructive) {
                    Task { await viewModel.disconnect(removeLocalData: true) }
                }
                Button("Reset local data", role: .destructive) {
                    Task { await viewModel.resetLocalData() }
                }
            }
        }
        .navigationTitle("Accounts")
        .overlay {
            if viewModel.isWorking {
                ProgressView()
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(isPresented: $viewModel.showLinkSheet) {
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
                        TextField("Setup token", text: $viewModel.setupToken, axis: .vertical)
                            .lineLimit(3...6)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("accounts.token")
                    }
                }
                .navigationTitle("Link SimpleFIN")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { viewModel.showLinkSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Link") {
                            Task { await viewModel.linkSimpleFIN() }
                        }
                        .disabled(viewModel.setupToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

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
                .accessibilityIdentifier("onboarding.demo")

                Button {
                    viewModel.showOnboarding = false
                    viewModel.showLinkSheet = true
                } label: {
                    Text("Link SimpleFIN")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("onboarding.link")

                Button("Skip for now") {
                    viewModel.dismissOnboarding()
                }
                .font(.footnote)
            }
            .padding(28)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium, .large])
    }
}
