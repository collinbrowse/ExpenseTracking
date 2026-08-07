import Foundation

/// Asks WidgetKit to refresh the cash-flow home-screen widget.
///
/// Implementations live outside CashFlowKit (WidgetKit is forbidden here). Features and
/// sync call this after local data changes so every widget instance recomputes **its own**
/// configured range from the shared store — not Home's currently selected range.
public protocol WidgetTimelineReloading: Sendable {
    func reloadCashFlowWidget()
}

/// Test / preview stand-in that records calls without touching WidgetKit.
public final class RecordingWidgetTimelineReloader: WidgetTimelineReloading, @unchecked Sendable {
    private let lock = NSLock()
    private var _reloadCount = 0

    public var reloadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _reloadCount
    }

    public init() {}

    public func reloadCashFlowWidget() {
        lock.lock()
        defer { lock.unlock() }
        _reloadCount += 1
    }
}

public struct NoOpWidgetTimelineReloader: WidgetTimelineReloading {
    public init() {}

    public func reloadCashFlowWidget() {}
}
