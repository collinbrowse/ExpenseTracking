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
    let resetter: LocalDataResetter
    let connectivity: ConnectivityMonitor
    let calculateNetCashFlow: CalculateNetCashFlowUseCase
    let useLargeDemoSeed: Bool

    init(inMemory: Bool = false, largeDemoSeed: Bool = false) throws {
        self.useLargeDemoSeed = largeDemoSeed
        let container = try ModelContainerFactory.make(
            inMemory: inMemory,
            appGroupID: NetSnapshotStore.defaultAppGroupID
        )
        self.modelContainer = container
        self.transactionRepository = SwiftDataTransactionRepository(modelContainer: container)
        self.accountRepository = SwiftDataAccountRepository(modelContainer: container)
        let demo = DemoBankLinkingService(
            seedSize: largeDemoSeed ? .large : .standard
        )
        let simpleFIN = SimpleFINBankLinkingService()
        let linking = CompositeBankLinkingService(demo: demo, simpleFIN: simpleFIN)
        self.bankLinking = linking
        self.syncServing = SyncCoordinator(
            modelContainer: container,
            bankLinking: linking
        )
        self.resetter = LocalDataResetter(modelContainer: container)
        self.connectivity = ConnectivityMonitor()
        self.calculateNetCashFlow = CalculateNetCashFlowUseCase()
    }
}
