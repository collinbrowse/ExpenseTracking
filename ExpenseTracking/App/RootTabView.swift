import SwiftUI

struct RootTabView: View {
    let container: DependencyContainer
    @State private var selectedTab: AppTab = .home
    @State private var homeViewModel: HomeViewModel
    @State private var transactionsViewModel: TransactionsViewModel
    @State private var accountsViewModel: AccountsViewModel

    init(container: DependencyContainer) {
        self.container = container
        _homeViewModel = State(
            initialValue: HomeViewModel(
                transactionRepository: container.transactionRepository,
                syncServing: container.syncServing,
                calculateNetCashFlow: container.calculateNetCashFlow,
                connectivity: container.connectivity
            )
        )
        _transactionsViewModel = State(
            initialValue: TransactionsViewModel(
                transactionRepository: container.transactionRepository,
                accountRepository: container.accountRepository,
                syncServing: container.syncServing
            )
        )
        _accountsViewModel = State(
            initialValue: AccountsViewModel(
                connectionLifecycle: container.connectionLifecycle,
                syncServing: container.syncServing,
                accountRepository: container.accountRepository,
                useLargeDemoSeed: container.useLargeDemoSeed
            )
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(viewModel: homeViewModel)
            }
            .tabItem { Label("Home", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppTab.home)

            NavigationStack {
                TransactionsView(viewModel: transactionsViewModel)
            }
            .tabItem { Label("Transactions", systemImage: "list.bullet") }
            .tag(AppTab.transactions)

            NavigationStack {
                AccountsView(viewModel: accountsViewModel) { accountID in
                    Task {
                        await transactionsViewModel.focusAccount(accountID)
                        selectedTab = .transactions
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .tabItem { Label("Accounts", systemImage: "building.columns") }
            .tag(AppTab.accounts)
        }
        .sheet(isPresented: $accountsViewModel.showOnboarding, onDismiss: {
            // Present link sheet only after onboarding fully dismisses (stacked sheets fail).
            if accountsViewModel.pendingLinkAfterOnboarding {
                selectedTab = .accounts
                accountsViewModel.presentPendingLinkIfNeeded()
            }
        }) {
            OnboardingView(viewModel: accountsViewModel)
        }
        .sheet(isPresented: $accountsViewModel.showLinkSheet) {
            SimpleFINLinkSheet(viewModel: accountsViewModel)
        }
        .alert(item: $accountsViewModel.errorAlert) { alert in
            switch alert.primaryAction {
            case .reconnect:
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("Reconnect")) {
                        accountsViewModel.performErrorAction(.reconnect)
                    },
                    secondaryButton: .cancel(Text("OK")) {
                        accountsViewModel.dismissErrorAlert()
                    }
                )
            case .syncNow:
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("Sync Now")) {
                        accountsViewModel.performErrorAction(.syncNow)
                    },
                    secondaryButton: .cancel(Text("OK")) {
                        accountsViewModel.dismissErrorAlert()
                    }
                )
            case .dismissOnly:
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK")) {
                        accountsViewModel.dismissErrorAlert()
                    }
                )
            }
        }
        .onChange(of: accountsViewModel.showLinkSheet) { _, isPresented in
            if isPresented {
                selectedTab = .accounts
            }
        }
        .onChange(of: accountsViewModel.storeEpoch) { _, _ in
            Task {
                await homeViewModel.reload(preferLoadingIndicator: !homeViewModel.hasData)
                await transactionsViewModel.resetAndLoad()
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .home {
                Task { await homeViewModel.reload(preferLoadingIndicator: false) }
            }
        }
    }
}
