import Foundation

/// Persists whether the user has enabled app lock. Non-secret preference (UserDefaults is fine).
public protocol AppLockPreferencesStoring: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool)
}
