import Foundation
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("AppLockPreferencesStore")
struct AppLockPreferencesStoreTests {
    @Test("Round-trips enabled flag")
    func roundTrip() {
        let suiteName = "AppLockPreferencesStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsAppLockPreferencesStore(defaults: defaults, key: "appLockEnabled")
        #expect(store.isEnabled() == false)

        store.setEnabled(true)
        #expect(store.isEnabled() == true)

        store.setEnabled(false)
        #expect(store.isEnabled() == false)
    }
}
