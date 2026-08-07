import SwiftUI
import SwiftData
import CashFlowData

@main
struct ExpenseTrackingApp: App {
    private let container: DependencyContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTesting") {
            Self.prepareForUITesting()
        }
        let largeSeed = arguments.contains("-largeDemoSeed")
        // Resilient SwiftData bootstrap — never crash launch on store migration.
        container = DependencyContainer(largeDemoSeed: largeSeed)
        // BGProcessingTask handlers must register before launch finishes.
        container.backgroundEnrichment.registerHandlers()
        container.backgroundEnrichment.scheduleUnattendedContinuation()
    }

    /// Deterministic UITest launch: empty store, no onboarding flag, no lock, no link secrets.
    private static func prepareForUITesting() {
        UserDefaults.standard.removeObject(forKey: "didCompleteOnboarding")
        UserDefaults.standard.set(false, forKey: "appLockEnabled")
        ModelContainerFactory.destroyPersistentStores(
            appGroupID: NetSnapshotStore.defaultAppGroupID
        )
        ModelContainerFactory.destroyPersistentStores(appGroupID: nil)
        try? KeychainAccessURLStore().delete()
        try? NetSnapshotStore().clear()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(container: container)
                .modelContainer(container.modelContainer)
        }
    }
}
