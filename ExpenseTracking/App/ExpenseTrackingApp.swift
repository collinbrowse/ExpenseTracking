import SwiftUI
import SwiftData

@main
struct ExpenseTrackingApp: App {
    private let container: DependencyContainer

    init() {
        let largeSeed = ProcessInfo.processInfo.arguments.contains("-largeDemoSeed")
        // Resilient SwiftData bootstrap — never crash launch on store migration.
        container = DependencyContainer(largeDemoSeed: largeSeed)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(container: container)
                .modelContainer(container.modelContainer)
        }
    }
}
