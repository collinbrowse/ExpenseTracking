import SwiftUI
import SwiftData
import CashFlowData

@main
struct ExpenseTrackingApp: App {
    private let container: DependencyContainer

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let uiTesting = arguments.contains("-uiTesting")
        if uiTesting {
            Self.prepareForUITesting()
        }
        let largeSeed = arguments.contains("-largeDemoSeed")
        // Resilient SwiftData bootstrap — never crash launch on store migration.
        container = DependencyContainer(largeDemoSeed: largeSeed, uiTesting: uiTesting)
        guard !uiTesting else { return }
        // BGProcessingTask handlers must register before launch finishes.
        container.backgroundEnrichment.registerHandlers()
        container.backgroundEnrichment.scheduleUnattendedContinuation()
    }

    /// Deterministic UITest launch: onboarding reset, no lock, no link secrets.
    /// Store wipe is unnecessary — `DependencyContainer(uiTesting:)` uses in-memory SwiftData.
    private static func prepareForUITesting() {
        UserDefaults.standard.removeObject(forKey: "didCompleteOnboarding")
        UserDefaults.standard.set(false, forKey: "appLockEnabled")
        try? KeychainAccessURLStore().delete()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(container: container)
                .modelContainer(container.modelContainer)
        }
    }
}
