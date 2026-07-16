import SwiftUI
import SwiftData

@main
struct ExpenseTrackingApp: App {
    private let container: DependencyContainer

    init() {
        let largeSeed = ProcessInfo.processInfo.arguments.contains("-largeDemoSeed")
        do {
            container = try DependencyContainer(largeDemoSeed: largeSeed)
        } catch {
            fatalError("Failed to create data stack: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(container: container)
                .modelContainer(container.modelContainer)
        }
    }
}
