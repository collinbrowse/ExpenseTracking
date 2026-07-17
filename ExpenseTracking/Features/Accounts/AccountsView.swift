import SwiftUI
import CashFlowKit

struct AccountsView: View {
    @Bindable var viewModel: AccountsViewModel
    var onSelectAccount: (AccountID) -> Void = { _ in }
    @State private var confirmAction: AccountsConfirmAction?

    var body: some View {
        List {
            if viewModel.hasOrphanLocalData {
                Section {
                    Text("Local accounts remain from a previous session, but nothing is linked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Erase everything…") {
                        confirmAction = .eraseEverything
                    }
                    .disabled(viewModel.isWorking)
                    Button("Link SimpleFIN (replaces local data)…") {
                        confirmAction = .linkReplacingData
                    }
                    .disabled(viewModel.isWorking)
                    Button("Load Demo (replaces local data)") {
                        confirmAction = .loadDemoReplacingData
                    }
                    .disabled(viewModel.isWorking)
                } header: {
                    Text("Leftover data")
                }
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

                if !viewModel.connection.isLinked && !viewModel.hasOrphanLocalData {
                    Button("Link SimpleFIN…") {
                        viewModel.beginLinkFlow()
                    }
                    .disabled(viewModel.isWorking)
                    .accessibilityIdentifier("accounts.link")

                    Button("Load Demo Data") {
                        Task { await viewModel.loadDemo() }
                    }
                    .disabled(viewModel.isWorking)
                    .accessibilityIdentifier("accounts.demo")
                } else if viewModel.connection.needsReauth {
                    Button("Reconnect SimpleFIN…") {
                        viewModel.beginLinkFlow()
                    }
                    .disabled(viewModel.isWorking)
                    .accessibilityIdentifier("accounts.link")
                }
            }

            Section("Accounts") {
                if viewModel.accounts.isEmpty {
                    Text("No accounts yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.accounts) { account in
                        Button {
                            onSelectAccount(account.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .foregroundStyle(.primary)
                                    Text(account.institutionName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(CurrencyFormatting.usd(account.balance))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("accounts.row.\(account.id.rawValue)")
                        .accessibilityLabel(
                            "\(account.name), \(account.institutionName), \(CurrencyFormatting.usd(account.balance))"
                        )
                        .contextMenu {
                            Button("Rename") {
                                viewModel.beginRename(account)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Rename") {
                                viewModel.beginRename(account)
                            }
                            .tint(.accentColor)
                        }
                    }
                }
            }

            Section("Manage") {
                Button("Disconnect (keep local data)", role: .destructive) {
                    confirmAction = .disconnectKeepData
                }
                .disabled(viewModel.isWorking || !viewModel.connection.isLinked)

                Button("Disconnect & delete local data", role: .destructive) {
                    confirmAction = .disconnectDeleteData
                }
                .disabled(viewModel.isWorking || !viewModel.connection.isLinked)

                Button("Clear local data (keep link)", role: .destructive) {
                    confirmAction = .resetKeepingLink
                }
                .disabled(viewModel.isWorking || !viewModel.connection.isLinked)

                Button("Erase everything", role: .destructive) {
                    confirmAction = .eraseEverything
                }
                .disabled(
                    viewModel.isWorking
                        || (!viewModel.connection.isLinked && viewModel.accounts.isEmpty)
                )
            }
        }
        .navigationTitle("Accounts")
        .overlay {
            if viewModel.isWorking && !viewModel.showLinkSheet {
                AccountsBusyOverlay(title: viewModel.workingTitle ?? "Working…")
            }
        }
        .overlay(alignment: .bottom) {
            if let banner = viewModel.statusBanner, !viewModel.showLinkSheet {
                Text(banner)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { viewModel.clearStatusBanner() }
                    .accessibilityIdentifier("accounts.statusBanner")
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.statusBanner)
        .confirmationDialog(
            confirmAction?.title(for: viewModel.connection.providerName) ?? "",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let confirmAction {
                Button(confirmAction.confirmButtonTitle, role: .destructive) {
                    let action = confirmAction
                    self.confirmAction = nil
                    Task {
                        switch action {
                        case .disconnectKeepData:
                            await viewModel.disconnect(removeLocalData: false)
                        case .disconnectDeleteData:
                            await viewModel.disconnect(removeLocalData: true)
                        case .resetKeepingLink:
                            await viewModel.resetLocalDataKeepingLink()
                        case .eraseEverything:
                            await viewModel.eraseEverything()
                        case .linkReplacingData:
                            viewModel.beginLinkFlow()
                        case .loadDemoReplacingData:
                            await viewModel.loadDemo()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                confirmAction = nil
            }
        } message: {
            Text(confirmAction?.message(for: viewModel.connection.providerName) ?? "")
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.renamingAccountID != nil },
            set: { if !$0 { viewModel.cancelRename() } }
        )) {
            renameSheet
        }
    }

    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Account name", text: $viewModel.renamingName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("accounts.rename.field")
                } footer: {
                    Text("This name stays on this device. Sync won’t overwrite it for this account.")
                }
            }
            .navigationTitle("Rename Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelRename() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.saveRename() }
                    }
                    .disabled(viewModel.renamingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("accounts.rename.save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private enum AccountsConfirmAction: Identifiable {
    case disconnectKeepData
    case disconnectDeleteData
    case resetKeepingLink
    case eraseEverything
    case linkReplacingData
    case loadDemoReplacingData

    var id: Self { self }

    func title(for providerName: String) -> String {
        switch self {
        case .disconnectKeepData:
            return "Disconnect \(providerName)?"
        case .disconnectDeleteData:
            return "Disconnect and delete data?"
        case .resetKeepingLink:
            return "Clear local data?"
        case .eraseEverything:
            return "Erase everything?"
        case .linkReplacingData:
            return "Replace local data?"
        case .loadDemoReplacingData:
            return "Replace with Demo data?"
        }
    }

    func message(for providerName: String) -> String {
        switch self {
        case .disconnectKeepData:
            return "This unlinks \(providerName) but keeps accounts and transactions on this device."
        case .disconnectDeleteData:
            return "This unlinks \(providerName) and permanently deletes local accounts and transactions."
        case .resetKeepingLink:
            return "This deletes local accounts and transactions. Your \(providerName) link stays so you can Sync Now."
        case .eraseEverything:
            return "This unlinks any connection and permanently deletes all local accounts and transactions."
        case .linkReplacingData:
            return "Linking SimpleFIN will erase leftover local accounts first. Demo and SimpleFIN cannot share data."
        case .loadDemoReplacingData:
            return "Loading Demo will erase leftover local accounts first. Demo and SimpleFIN cannot share data."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .disconnectKeepData: return "Disconnect"
        case .disconnectDeleteData: return "Disconnect & Delete"
        case .resetKeepingLink: return "Clear Data"
        case .eraseEverything: return "Erase Everything"
        case .linkReplacingData: return "Continue"
        case .loadDemoReplacingData: return "Load Demo"
        }
    }
}

struct AccountsBusyOverlay: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
            ProgressView(title)
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("accounts.busy")
        .accessibilityLabel(title)
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
