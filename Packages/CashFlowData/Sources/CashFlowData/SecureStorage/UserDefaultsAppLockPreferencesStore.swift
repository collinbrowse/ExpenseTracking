import Foundation
import CashFlowKit

public final class UserDefaultsAppLockPreferencesStore: AppLockPreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "appLockEnabled"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func isEnabled() -> Bool {
        defaults.bool(forKey: key)
    }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }
}
