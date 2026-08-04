import Foundation
import Observation
import SwiftUI
import CashFlowKit

@MainActor
@Observable
final class AppLockViewModel {
    static let graceInterval: TimeInterval = 15

    private let preferences: any AppLockPreferencesStoring
    private let authenticator: any DeviceAuthenticationServing
    private let graceInterval: TimeInterval
    private let now: () -> Date

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isPrivacyCoverVisible: Bool
    private(set) var isSceneActive: Bool = true
    private(set) var isAuthenticating: Bool = false
    private(set) var unlockErrorMessage: String?
    private(set) var settingsErrorMessage: String?

    private var becameInactiveAt: Date?
    private var didAutoPromptThisActiveSession = false

    var biometryDisplayName: String {
        authenticator.biometryDisplayName
    }

    var canAuthenticate: Bool {
        authenticator.canAuthenticate
    }

    var shouldShowOverlay: Bool {
        isLocked || isPrivacyCoverVisible
    }

    var showUnlockControls: Bool {
        isLocked && isSceneActive
    }

    var requireLockToggleTitle: String {
        "Require \(biometryDisplayName)"
    }

    init(
        preferences: any AppLockPreferencesStoring,
        authenticator: any DeviceAuthenticationServing,
        graceInterval: TimeInterval = AppLockViewModel.graceInterval,
        now: @escaping () -> Date = { Date() }
    ) {
        self.preferences = preferences
        self.authenticator = authenticator
        self.graceInterval = graceInterval
        self.now = now
        let enabled = preferences.isEnabled()
        self.isEnabled = enabled
        self.isLocked = enabled
        self.isPrivacyCoverVisible = enabled
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            handleBecameActive()
        case .inactive, .background:
            handleLeftActive()
        @unknown default:
            break
        }
    }

    func onAppear() {
        if isEnabled && isLocked && isSceneActive && !didAutoPromptThisActiveSession {
            didAutoPromptThisActiveSession = true
            Task { await unlock() }
        }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        unlockErrorMessage = nil
        defer { isAuthenticating = false }

        do {
            try await authenticator.authenticate(reason: "Unlock Cash Flow")
            isLocked = false
            isPrivacyCoverVisible = false
            unlockErrorMessage = nil
        } catch let error as CashFlowError where error == .cancelled {
            // Stay locked; user can tap Unlock again.
        } catch let error as CashFlowError where error == .authenticationUnavailable {
            unlockErrorMessage = "Device authentication is unavailable. Set a passcode in Settings."
        } catch {
            unlockErrorMessage = "Could not unlock. Try again."
        }
    }

    /// Enables or disables app lock after a successful authentication challenge.
    func setEnabled(_ enabled: Bool) async {
        settingsErrorMessage = nil
        guard enabled != isEnabled else { return }

        if enabled {
            guard authenticator.canAuthenticate else {
                settingsErrorMessage = "Turn on a device passcode to use app lock."
                return
            }
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let reason = enabled
            ? "Enable \(biometryDisplayName) to lock Cash Flow"
            : "Confirm to turn off app lock"

        do {
            try await authenticator.authenticate(reason: reason)
            preferences.setEnabled(enabled)
            isEnabled = enabled
            if enabled {
                isLocked = false
                isPrivacyCoverVisible = false
            } else {
                isLocked = false
                isPrivacyCoverVisible = false
                becameInactiveAt = nil
            }
        } catch let error as CashFlowError where error == .cancelled {
            // Leave preference unchanged.
        } catch let error as CashFlowError where error == .authenticationUnavailable {
            settingsErrorMessage = "Device authentication is unavailable. Set a passcode in Settings."
        } catch {
            settingsErrorMessage = "Could not update app lock. Try again."
        }
    }

    // MARK: - Scene

    private func handleLeftActive() {
        isSceneActive = false
        didAutoPromptThisActiveSession = false
        guard isEnabled else { return }
        becameInactiveAt = now()
        isPrivacyCoverVisible = true
    }

    private func handleBecameActive() {
        isSceneActive = true
        guard isEnabled else {
            isLocked = false
            isPrivacyCoverVisible = false
            becameInactiveAt = nil
            return
        }

        if isLocked {
            isPrivacyCoverVisible = true
            if !didAutoPromptThisActiveSession {
                didAutoPromptThisActiveSession = true
                Task { await unlock() }
            }
            return
        }

        let inactiveAt = becameInactiveAt
        becameInactiveAt = nil

        if let inactiveAt, now().timeIntervalSince(inactiveAt) >= graceInterval {
            isLocked = true
            isPrivacyCoverVisible = true
            if !didAutoPromptThisActiveSession {
                didAutoPromptThisActiveSession = true
                Task { await unlock() }
            }
        } else {
            isPrivacyCoverVisible = false
        }
    }
}
