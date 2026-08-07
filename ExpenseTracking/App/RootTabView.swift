import SwiftUI
import CashFlowKit

struct RootTabView: View {
    let container: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home
    @State private var homeViewModel: HomeViewModel
    @State private var transactionsViewModel: TransactionsViewModel
    @State private var insightsViewModel: InsightsViewModel
    @State private var accountsViewModel: AccountsViewModel
    @State private var appLockViewModel: AppLockViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var pendingEnrichmentEstimate: EnrichmentWorkEstimate?
    @State private var showEnrichmentPrompt = false

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
        let lock = AppLockViewModel(
            preferences: container.appLockPreferences,
            authenticator: container.deviceAuthentication
        )
        _appLockViewModel = State(initialValue: lock)
        _settingsViewModel = State(
            initialValue: SettingsViewModel(
                ruleRepository: container.categorizationRuleRepository,
                ruleApplying: container.categorizationRuleApplying,
                accountRepository: container.accountRepository,
                tagRepository: container.tagRepository,
                ruleDrafting: container.categorizationRuleDrafting,
                availabilityChecker: container.onDeviceModelAvailability,
                appLock: lock,
                syncServing: container.syncServing,
                backgroundEnrichment: container.backgroundEnrichment,
                cleanupState: container.titleCleanupState
            )
        )
    }

    var body: some View {
        tabContent
            .modifier(RootSheetsModifier(
                accountsViewModel: accountsViewModel,
                selectedTab: $selectedTab,
                showEnrichmentPrompt: $showEnrichmentPrompt,
                pendingEnrichmentEstimate: pendingEnrichmentEstimate,
                onContinueEnrichment: continueEnrichmentDrain,
                onDeferEnrichment: deferEnrichmentDrain
            ))
            .modifier(RootLifecycleModifier(
                selectedTab: $selectedTab,
                homeViewModel: homeViewModel,
                transactionsViewModel: transactionsViewModel,
                insightsViewModel: insightsViewModel,
                accountsViewModel: accountsViewModel,
                settingsViewModel: settingsViewModel,
                appLockViewModel: appLockViewModel,
                scenePhase: scenePhase,
                onStoreEpoch: handleStoreEpoch,
                onScenePhase: handleScenePhase
            ))
    }

    @ViewBuilder
    private var tabContent: some View {
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
                InsightsView(viewModel: insightsViewModel)
            }
            .tabItem { Label("Insights", systemImage: "chart.pie") }
            .tag(AppTab.insights)

            NavigationStack {
                SettingsView(
                    viewModel: settingsViewModel,
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
            .badge(settingsViewModel.settingsTabBadge)
            .tag(AppTab.settings)
        }
    }

    private func handleStoreEpoch() async {
        await homeViewModel.reload(preferLoadingIndicator: !homeViewModel.hasData)
        await transactionsViewModel.resetAndLoad()
        await insightsViewModel.reload(preferLoadingIndicator: false)
        await presentEnrichmentPromptIfNeeded()
        await settingsViewModel.reloadHistoryStatus()
    }

    private func handleBecameActive() async {
        await presentEnrichmentPromptIfNeeded()
        // Do not silently enrich here. Post-sync and BG tasks own opportunistic work;
        // Settings' idle "N titles left" should only move when cleanup is visible or the
        // user opens / refreshes the screen — not while they're staring at it.
        if settingsViewModel.isCleaningUpTitles {
            return
        }
        await settingsViewModel.reloadHistoryStatus(refreshTitleBacklog: false)
    }

    private func handleScenePhase(_ phase: ScenePhase) async {
        await container.backgroundEnrichment.setAppForeground(phase == .active)
        if phase == .active {
            await handleBecameActive()
        }
    }

    private func presentEnrichmentPromptIfNeeded() async {
        guard let estimate = await container.syncServing.consumePendingEnrichmentPrompt(),
              estimate.shouldPrompt
        else { return }
        pendingEnrichmentEstimate = estimate
        showEnrichmentPrompt = true
    }

    private func continueEnrichmentDrain() {
        showEnrichmentPrompt = false
        let expected = pendingEnrichmentEstimate?.backlogCount
        Task {
            // Same path as Settings → Clean up transactions.
            await settingsViewModel.startTitleCleanup(expectedUntitled: expected)
        }
    }

    private func deferEnrichmentDrain() {
        showEnrichmentPrompt = false
        Task {
            _ = await container.transactionEnrichment.enrichAfterSync(skipIfLargeBacklog: false)
            await settingsViewModel.reloadHistoryStatus()
        }
    }
}

private struct RootSheetsModifier: ViewModifier {
    @Bindable var accountsViewModel: AccountsViewModel
    @Binding var selectedTab: AppTab
    @Binding var showEnrichmentPrompt: Bool
    let pendingEnrichmentEstimate: EnrichmentWorkEstimate?
    let onContinueEnrichment: () -> Void
    let onDeferEnrichment: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $accountsViewModel.showOnboarding, onDismiss: {
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
                accountsErrorAlert(alert)
            }
            .sheet(isPresented: $showEnrichmentPrompt) {
                EnrichmentPromptSheet(
                    estimate: pendingEnrichmentEstimate,
                    onContinue: onContinueEnrichment,
                    onNotNow: onDeferEnrichment
                )
            }
    }

    private func accountsErrorAlert(_ alert: AccountsErrorAlert) -> Alert {
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
}

private struct RootLifecycleModifier: ViewModifier {
    @Binding var selectedTab: AppTab
    let homeViewModel: HomeViewModel
    let transactionsViewModel: TransactionsViewModel
    let insightsViewModel: InsightsViewModel
    @Bindable var accountsViewModel: AccountsViewModel
    let settingsViewModel: SettingsViewModel
    @Bindable var appLockViewModel: AppLockViewModel
    let scenePhase: ScenePhase
    let onStoreEpoch: () async -> Void
    let onScenePhase: (ScenePhase) async -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: accountsViewModel.showLinkSheet) { _, isPresented in
                if isPresented {
                    selectedTab = .settings
                }
            }
            .onChange(of: accountsViewModel.storeEpoch) { _, _ in
                Task { await onStoreEpoch() }
            }
            .onChange(of: selectedTab) { _, tab in
                handleTabChange(tab)
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
                Task { await onScenePhase(phase) }
            }
        .onAppear {
            appLockViewModel.handleScenePhase(scenePhase)
            appLockViewModel.onAppear()
            settingsViewModel.startObservingEnrichmentProgress()
            Task { await onScenePhase(scenePhase) }
        }
    }

    private func handleTabChange(_ tab: AppTab) {
        switch tab {
        case .home:
            Task { await homeViewModel.reload(preferLoadingIndicator: false) }
        case .settings:
            Task {
                await accountsViewModel.refreshStatus()
                await settingsViewModel.reloadHistoryStatus()
            }
        case .insights:
            Task { await insightsViewModel.reload(preferLoadingIndicator: false) }
        case .transactions:
            Task {
                await transactionsViewModel.refreshTagsIfNeeded()
                await transactionsViewModel.resetAndLoad()
            }
        }
    }
}

private struct EnrichmentPromptSheet: View {
    let estimate: EnrichmentWorkEstimate?
    let onContinue: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Improve transactions?")
                    .font(.title2.bold())
                if let estimate {
                    Text(
                        "\(estimate.untitledCount) still show raw bank text and \(estimate.undefinedCount) need a category. About \(estimate.distinctMerchantLookups) unique merchants need a one-time lookup."
                    )
                    .foregroundStyle(.secondary)
                }
                Text("Cleanup uses on-device Apple Intelligence. Progress shows under Settings (and in the system indicator if you leave).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue Cleanup", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                Button("Not Now", action: onNotNow)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("Transaction Cleanup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("enrichment.prompt")
    }
}
