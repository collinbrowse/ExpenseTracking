import Foundation
import CashFlowKit

public final class UserDefaultsTitleCleanupStateStore: TitleCleanupStateStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "titleCleanupPaused"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func isPaused() -> Bool {
        defaults.bool(forKey: key)
    }

    public func setPaused(_ paused: Bool) {
        defaults.set(paused, forKey: key)
    }
}
