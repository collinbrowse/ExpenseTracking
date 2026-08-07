import SwiftUI
import SwiftData
import CashFlowData

@main
struct ExpenseTrackingApp: App {
    private let container: DependencyContainer
    private let isUITesting: Bool

    init() {
        let uiTesting = Self.isUITestingLaunch
        self.isUITesting = uiTesting
        if uiTesting {
            Self.prepareForUITesting()
        }
        let largeSeed = ProcessInfo.processInfo.arguments.contains("-largeDemoSeed")
        // Resilient SwiftData bootstrap — never crash launch on store migration.
        container = DependencyContainer(largeDemoSeed: largeSeed, uiTesting: uiTesting)
        if uiTesting {
            do {
                try UITestDemoSeeder.seedStandardDemo(into: container.modelContainer)
                UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")
            } catch {
                assertionFailure("UITest demo seed failed: \(error)")
            }
            return
        }
        // BGProcessingTask handlers must register before launch finishes.
        container.backgroundEnrichment.registerHandlers()
        container.backgroundEnrichment.scheduleUnattendedContinuation()
    }

    private static var isUITestingLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
            || ProcessInfo.processInfo.environment["UITESTING"] == "1"
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
                .accessibilityIdentifier(isUITesting ? "uiTesting.root" : "app.root")
        }
    }
}
