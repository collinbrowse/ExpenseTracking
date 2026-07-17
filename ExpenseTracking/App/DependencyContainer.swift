import Foundation
import SwiftData
import CashFlowKit
import CashFlowData

@MainActor
final class DependencyContainer {
    let modelContainer: ModelContainer
    let transactionRepository: any TransactionRepository
    let accountRepository: any AccountRepository
    let bankLinking: CompositeBankLinkingService
    let syncServing: SyncCoordinator
    let connectionLifecycle: any ConnectionLifecycleServing
    let resetter: LocalDataResetter
    let connectivity: ConnectivityMonitor
    let calculateNetCashFlow: CalculateNetCashFlowUseCase
    let useLargeDemoSeed: Bool

    /// Launch-safe: SwiftData load/migration failures wipe and fall back; never fails for disk issues.
    convenience init(largeDemoSeed: Bool = false) {
        self.init(
            modelContainer: ModelContainerFactory.makeResilient(
                appGroupID: NetSnapshotStore.defaultAppGroupID
            ),
            largeDemoSeed: largeDemoSeed
        )
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
        self.transactionRepository = SwiftDataTransactionRepository(modelContainer: modelContainer)
        self.accountRepository = SwiftDataAccountRepository(modelContainer: modelContainer)
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
            snapshotStore: snapshotStore
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
    }
}
