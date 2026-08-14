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
                    Button("Link SimpleFIN…") {
                        confirmAction = .linkWithLocalDataChoice
                    }
                    .disabled(viewModel.isWorking)
                    Button("Load Demo…") {
                        confirmAction = .loadDemoWithLocalDataChoice
                    }
                    .disabled(viewModel.isWorking)
                } header: {
                    Text("Leftover data")
                }
            }

            Section("Connection") {
                LabeledContent("Provider", value: viewModel.connection.providerName)
                LabeledContent("Status", value: viewModel.connectionStatusLabel)
                    .accessibilityIdentifier("accounts.connectionStatus")
                if let synced = viewModel.connection.lastSuccessfulSyncAt {
                    LabeledContent("Last sync", value: DateFormatting.medium(synced))
                }
                if viewModel.hasAccountSyncIssues {
                    Text(
                        "One or more accounts didn’t sync cleanly. Try Sync Now after fixing the bank connection at SimpleFIN Bridge, or reconnect with a new token."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("accounts.syncIssueGuidance")
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
                } else if viewModel.showsReconnectAction {
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
                            AccountRowView(
                                account: account,
                                syncDisplay: viewModel.syncDisplay(for: account)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("accounts.row.\(account.id.rawValue)")
                        .accessibilityLabel(accountAccessibilityLabel(account))
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
                AccountsBusyOverlay(
                    title: viewModel.busyOverlayTitle,
                    progress: viewModel.syncProgress
                )
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
                switch confirmAction {
                case .linkWithLocalDataChoice:
                    Button("Keep local data") {
                        self.confirmAction = nil
                        viewModel.pendingLinkDeletesLocalData = false
                        viewModel.beginLinkFlow()
                    }
                    Button("Delete local data", role: .destructive) {
                        self.confirmAction = nil
                        viewModel.pendingLinkDeletesLocalData = true
                        viewModel.beginLinkFlow()
                    }
                case .loadDemoWithLocalDataChoice:
                    Button("Keep local data") {
                        self.confirmAction = nil
                        Task { await viewModel.loadDemo(deleteLocalData: false) }
                    }
                    Button("Delete local data", role: .destructive) {
                        self.confirmAction = nil
                        Task { await viewModel.loadDemo(deleteLocalData: true) }
                    }
                default:
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
                            case .linkWithLocalDataChoice, .loadDemoWithLocalDataChoice:
                                break
                            }
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
            AccountRenameSheet(viewModel: viewModel)
        }
    }
}

private enum AccountsConfirmAction: Identifiable {
    case disconnectKeepData
    case disconnectDeleteData
    case resetKeepingLink
    case eraseEverything
    case linkWithLocalDataChoice
    case loadDemoWithLocalDataChoice

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
        case .linkWithLocalDataChoice:
            return "Local data on this device"
        case .loadDemoWithLocalDataChoice:
            return "Local data on this device"
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
        case .linkWithLocalDataChoice:
            return "Keep existing accounts and transactions (including CSV imports), or delete them before linking SimpleFIN. Sync will add bank accounts alongside anything you keep."
        case .loadDemoWithLocalDataChoice:
            return "Keep existing accounts and transactions, or delete them before loading Demo data."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .disconnectKeepData: return "Disconnect"
        case .disconnectDeleteData: return "Disconnect & Delete"
        case .resetKeepingLink: return "Clear Data"
        case .eraseEverything: return "Erase Everything"
        case .linkWithLocalDataChoice, .loadDemoWithLocalDataChoice: return "Continue"
        }
    }
}

private extension AccountsView {
    func accountAccessibilityLabel(_ account: Account) -> String {
        let balance = CurrencyFormatting.usd(account.balance)
        switch viewModel.syncDisplay(for: account) {
        case .healthy:
            return "\(account.name), \(account.institutionName), \(balance), sync OK"
        case .issue(let message):
            return "\(account.name), \(account.institutionName), \(balance), sync issue: \(message)"
        case .none:
            return "\(account.name), \(account.institutionName), \(balance)"
        }
    }
}
