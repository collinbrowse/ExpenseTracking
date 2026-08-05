import Foundation
import SwiftData
import CashFlowKit
import CashFlowData

@MainActor
final class DependencyContainer {
    let modelContainer: ModelContainer
    let transactionRepository: any TransactionRepository
    let accountRepository: any AccountRepository
    let categorizationRuleRepository: any CategorizationRuleRepository
    let categorizationRuleApplying: any CategorizationRuleApplying
    let tagRepository: any TagRepository
    let bankLinking: CompositeBankLinkingService
    let syncServing: SyncCoordinator
    let connectionLifecycle: any ConnectionLifecycleServing
    let resetter: LocalDataResetter
    let connectivity: ConnectivityMonitor
    let calculateNetCashFlow: CalculateNetCashFlowUseCase
    let calculateSpendingBreakdown: CalculateSpendingBreakdownUseCase
    let appLockPreferences: any AppLockPreferencesStoring
    let deviceAuthentication: any DeviceAuthenticationServing
    let onDeviceModelAvailability: any OnDeviceModelAvailabilityChecking
    let descriptionEnricher: any TransactionDescriptionEnriching
    let categoryEnricher: any TransactionCategoryEnriching
    let transactionEnrichment: any TransactionEnrichmentRunning
    let transactionAssistant: any TransactionAssistantServing
    let categorizationRuleDrafting: any CategorizationRuleDrafting
    let useLargeDemoSeed: Bool

    /// Launch-safe: SwiftData load/migration failures wipe and fall back; never fails for disk issues.
    convenience init(largeDemoSeed: Bool = false) {
        // XCTest / unsigned CI hosts often lack App Group entitlements; SwiftData traps
        // (does not throw) if `groupContainer` is requested without them.
        let appGroupID = Self.isRunningUnitTests
            ? nil
            : NetSnapshotStore.defaultAppGroupID
        self.init(
            modelContainer: ModelContainerFactory.makeResilient(appGroupID: appGroupID),
            largeDemoSeed: largeDemoSeed
        )
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Tests / previews that need an explicit in-memory (or throw-on-failure) stack.
    convenience init(inMemory: Bool, largeDemoSeed: Bool = false) throws {
        let container = try ModelContainerFactory.make(
            inMemory: inMemory,
            appGroupID: NetSnapshotStore.defaultAppGroupID
        )
        self.init(modelContainer: container, largeDemoSeed: largeDemoSeed)
    }

    private init(modelContainer: ModelContainer, largeDemoSeed: Bool) {
        self.useLargeDemoSeed = largeDemoSeed
        self.modelContainer = modelContainer
        let transactionRepository = SwiftDataTransactionRepository(modelContainer: modelContainer)
        self.transactionRepository = transactionRepository
        self.accountRepository = SwiftDataAccountRepository(modelContainer: modelContainer)
        let categorizationRuleRepository = SwiftDataCategorizationRuleRepository(
            modelContainer: modelContainer
        )
        self.categorizationRuleRepository = categorizationRuleRepository
        self.categorizationRuleApplying = CategorizationRuleReapplier(
            modelContainer: modelContainer
        )
        let tagRepository = SwiftDataTagRepository(modelContainer: modelContainer)
        self.tagRepository = tagRepository

        let availability = AppleIntelligenceAvailabilityChecker()
        self.onDeviceModelAvailability = availability
        let descriptionEnricher = DescriptionEnricherFactory.make(availability: availability)
        self.descriptionEnricher = descriptionEnricher
        let categoryEnricher = CategoryEnricherFactory.make(availability: availability)
        self.categoryEnricher = categoryEnricher
        let enrichment = TransactionEnrichmentCoordinator(
            availability: availability,
            descriptionEnricher: descriptionEnricher,
            categoryEnricher: categoryEnricher,
            transactionRepository: transactionRepository,
            ruleRepository: categorizationRuleRepository
        )
        self.transactionEnrichment = enrichment
        self.transactionAssistant = TransactionAssistantFactory.make(
            availability: availability,
            transactionRepository: transactionRepository,
            tagRepository: tagRepository,
            accountRepository: accountRepository,
            ruleRepository: categorizationRuleRepository,
            ruleApplying: categorizationRuleApplying
        )
        self.categorizationRuleDrafting = CategorizationRuleDraftingFactory.make(
            availability: availability
        )

        let demo = DemoBankLinkingService(
            seedSize: largeDemoSeed ? .large : .standard
        )
        let simpleFIN = SimpleFINBankLinkingService()
        let linking = CompositeBankLinkingService(demo: demo, simpleFIN: simpleFIN)
        self.bankLinking = linking
        let snapshotStore = NetSnapshotStore()
        let sync = SyncCoordinator(
            modelContainer: modelContainer,
            bankLinking: linking,
            snapshotStore: snapshotStore,
            enrichment: enrichment
        )
        self.syncServing = sync
        let resetter = LocalDataResetter(
            modelContainer: modelContainer,
            snapshotStore: snapshotStore
        )
        self.resetter = resetter
        self.connectionLifecycle = ConnectionLifecycleService(
            bankLinking: linking,
            sync: sync,
            resetter: resetter
        )
        self.connectivity = ConnectivityMonitor()
        self.calculateNetCashFlow = CalculateNetCashFlowUseCase()
        self.calculateSpendingBreakdown = CalculateSpendingBreakdownUseCase()
        self.appLockPreferences = UserDefaultsAppLockPreferencesStore()
        self.deviceAuthentication = LocalAuthenticationDeviceAuthenticator()
    }
}
