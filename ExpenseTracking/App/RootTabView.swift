import SwiftUI

struct RootTabView: View {
    let container: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home
    @State private var homeViewModel: HomeViewModel
    @State private var transactionsViewModel: TransactionsViewModel
    @State private var insightsViewModel: InsightsViewModel
    @State private var accountsViewModel: AccountsViewModel
    @State private var appLockViewModel: AppLockViewModel

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
                tagRepository: container.tagRepository,
                syncServing: container.syncServing,
                ruleRepository: container.categorizationRuleRepository,
                ruleApplying: container.categorizationRuleApplying,
                ruleDrafting: container.categorizationRuleDrafting,
                availabilityChecker: container.onDeviceModelAvailability
            )
        )
        _insightsViewModel = State(
            initialValue: InsightsViewModel(
                transactionRepository: container.transactionRepository,
                tagRepository: container.tagRepository,
                syncServing: container.syncServing,
                calculateSpendingBreakdown: container.calculateSpendingBreakdown
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
        _appLockViewModel = State(
            initialValue: AppLockViewModel(
                preferences: container.appLockPreferences,
                authenticator: container.deviceAuthentication
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
                TransactionsView(
                    viewModel: transactionsViewModel,
                    makeAssistantViewModel: {
                        AssistantViewModel(
                            availabilityChecker: container.onDeviceModelAvailability,
                            assistant: container.transactionAssistant,
                            transactionRepository: container.transactionRepository
                        )
                    }
                )
            }
            .tabItem { Label("Transactions", systemImage: "list.bullet") }
            .tag(AppTab.transactions)

            NavigationStack {
                InsightsView(
                    viewModel: insightsViewModel,
                    onViewTransactions: { categoryID, tagID, dateOption, start, end in
                        Task {
                            await transactionsViewModel.focusInsights(
                                categoryID: categoryID,
                                tagID: tagID,
                                dateOption: dateOption,
                                customStart: start,
                                customEnd: end
                            )
                            selectedTab = .transactions
                        }
                    }
                )
            }
            .tabItem { Label("Insights", systemImage: "chart.pie") }
            .tag(AppTab.insights)

            NavigationStack {
                SettingsView(
                    viewModel: SettingsViewModel(
                        ruleRepository: container.categorizationRuleRepository,
                        ruleApplying: container.categorizationRuleApplying,
                        accountRepository: container.accountRepository,
                        tagRepository: container.tagRepository,
                        ruleDrafting: container.categorizationRuleDrafting,
                        availabilityChecker: container.onDeviceModelAvailability,
                        appLock: appLockViewModel
                    ),
                    accountsViewModel: accountsViewModel,
                    onSelectAccount: { accountID in
                        Task {
                            await transactionsViewModel.focusAccount(accountID)
                            selectedTab = .transactions
                        }
                    }
                )
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .sheet(isPresented: $accountsViewModel.showOnboarding, onDismiss: {
            // Present link sheet only after onboarding fully dismisses (stacked sheets fail).
            if accountsViewModel.pendingLinkAfterOnboarding {
                selectedTab = .settings
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
                selectedTab = .settings
            }
        }
        .onChange(of: accountsViewModel.storeEpoch) { _, _ in
            Task {
                await homeViewModel.reload(preferLoadingIndicator: !homeViewModel.hasData)
                await transactionsViewModel.resetAndLoad()
                await insightsViewModel.reload(preferLoadingIndicator: false)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            switch tab {
            case .home:
                Task { await homeViewModel.reload(preferLoadingIndicator: false) }
            case .settings:
                // Home / Transactions sync can update durable syncIssue while this tab is idle.
                Task { await accountsViewModel.refreshStatus() }
            case .insights:
                Task { await insightsViewModel.reload(preferLoadingIndicator: false) }
            case .transactions:
                // Assistant (and other mutations) may have changed categories/tags while
                // this tab stayed mounted — reload so the list/editor aren't stale.
                Task {
                    await transactionsViewModel.refreshTagsIfNeeded()
                    await transactionsViewModel.resetAndLoad()
                }
            }
        }
        .overlay {
            if appLockViewModel.shouldShowOverlay {
                AppLockGateView(
                    biometryDisplayName: appLockViewModel.biometryDisplayName,
                    showUnlockControls: appLockViewModel.showUnlockControls,
                    isAuthenticating: appLockViewModel.isAuthenticating,
                    errorMessage: appLockViewModel.unlockErrorMessage,
                    onUnlock: {
                        Task { await appLockViewModel.unlock() }
                    }
                )
                .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            appLockViewModel.handleScenePhase(phase)
        }
        .onAppear {
            appLockViewModel.handleScenePhase(scenePhase)
            appLockViewModel.onAppear()
        }
    }
}
