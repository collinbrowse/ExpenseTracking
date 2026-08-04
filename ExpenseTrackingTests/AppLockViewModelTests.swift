import Foundation
import Testing
import SwiftUI
import CashFlowKit
@testable import ExpenseTracking

@Suite("AppLockViewModel")
@MainActor
struct AppLockViewModelTests {
    @Test("Launch starts locked when preference is enabled")
    func launchLockedWhenEnabled() {
        let prefs = MockAppLockPreferences(enabled: true)
        let auth = MockDeviceAuthenticator()
        let vm = AppLockViewModel(preferences: prefs, authenticator: auth)
        #expect(vm.isEnabled)
        #expect(vm.isLocked)
        #expect(vm.shouldShowOverlay)
    }

    @Test("Disabled never locks on resume")
    func disabledNeverLocks() {
        let prefs = MockAppLockPreferences(enabled: false)
        let auth = MockDeviceAuthenticator()
        let vm = AppLockViewModel(preferences: prefs, authenticator: auth)
        vm.handleScenePhase(.background)
        #expect(!vm.isPrivacyCoverVisible)
        vm.handleScenePhase(.active)
        #expect(!vm.isLocked)
        #expect(!vm.shouldShowOverlay)
    }

    @Test("Within grace period resume stays unlocked")
    func withinGraceStaysUnlocked() async {
        var current = Date(timeIntervalSince1970: 1_000)
        let prefs = MockAppLockPreferences(enabled: false)
        let auth = MockDeviceAuthenticator()
        let vm = AppLockViewModel(
            preferences: prefs,
            authenticator: auth,
            graceInterval: 15,
            now: { current }
        )
        await vm.setEnabled(true)
        #expect(!vm.isLocked)

        vm.handleScenePhase(.background)
        #expect(vm.isPrivacyCoverVisible)
        current = current.addingTimeInterval(14)
        vm.handleScenePhase(.active)
        #expect(!vm.isLocked)
        #expect(!vm.isPrivacyCoverVisible)
    }

    @Test("Past grace period resume locks")
    func pastGraceLocks() async {
        var current = Date(timeIntervalSince1970: 1_000)
        let prefs = MockAppLockPreferences(enabled: false)
        let auth = MockDeviceAuthenticator()
        let vm = AppLockViewModel(
            preferences: prefs,
            authenticator: auth,
            graceInterval: 15,
            now: { current }
        )
        await vm.setEnabled(true)
        #expect(!vm.isLocked)

        vm.handleScenePhase(.background)
        current = current.addingTimeInterval(15)
        // Prevent auto-unlock from clearing the locked state before assertion.
        auth.nextError = CashFlowError.cancelled
        vm.handleScenePhase(.active)
        #expect(vm.isLocked)
        #expect(vm.shouldShowOverlay)
    }

    @Test("Enable requires successful authentication")
    func enableRequiresAuth() async {
        let prefs = MockAppLockPreferences(enabled: false)
        let auth = MockDeviceAuthenticator()
        auth.nextError = CashFlowError.cancelled
        let vm = AppLockViewModel(preferences: prefs, authenticator: auth)

        await vm.setEnabled(true)
        #expect(!vm.isEnabled)
        #expect(prefs.isEnabled() == false)
        #expect(auth.authenticateCallCount == 1)

        auth.nextError = nil
        await vm.setEnabled(true)
        #expect(vm.isEnabled)
        #expect(prefs.isEnabled() == true)
    }

    @Test("Enable fails closed when authentication unavailable")
    func enableFailsWhenUnavailable() async {
        let prefs = MockAppLockPreferences(enabled: false)
        let auth = MockDeviceAuthenticator()
        auth.canAuthenticate = false
        let vm = AppLockViewModel(preferences: prefs, authenticator: auth)

        await vm.setEnabled(true)
        #expect(!vm.isEnabled)
        #expect(auth.authenticateCallCount == 0)
        #expect(vm.settingsErrorMessage != nil)
    }

    @Test("Successful unlock clears locked state")
    func unlockClearsLock() async {
        let prefs = MockAppLockPreferences(enabled: true)
        let auth = MockDeviceAuthenticator()
        let vm = AppLockViewModel(preferences: prefs, authenticator: auth)
        #expect(vm.isLocked)

        await vm.unlock()
        #expect(!vm.isLocked)
        #expect(!vm.shouldShowOverlay)
        #expect(auth.authenticateCallCount == 1)
    }
}

// MARK: - Fakes

private final class MockAppLockPreferences: AppLockPreferencesStoring, @unchecked Sendable {
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func isEnabled() -> Bool { enabled }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }
}

private final class MockDeviceAuthenticator: DeviceAuthenticationServing, @unchecked Sendable {
    var canAuthenticate = true
    var biometryDisplayName = "Face ID"
    var nextError: Error?
    var authenticateCallCount = 0

    func authenticate(reason: String) async throws {
        authenticateCallCount += 1
        if let nextError {
            let error = nextError
            self.nextError = nil
            throw error
        }
    }
}
