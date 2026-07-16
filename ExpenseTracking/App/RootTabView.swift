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
                bankLinking: container.bankLinking,
                syncServing: container.syncServing,
                accountRepository: container.accountRepository,
                resetter: container.resetter,
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
                AccountsView(viewModel: accountsViewModel)
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
        .sheet(isPresented: $accountsViewModel.showOnboarding) {
            OnboardingView(viewModel: accountsViewModel)
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
