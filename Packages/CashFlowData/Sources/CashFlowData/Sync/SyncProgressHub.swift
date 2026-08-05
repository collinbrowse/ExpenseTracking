import Foundation
import CashFlowKit

/// Fan-out hub for sync progress. Safe to call from actors and nonisolated contexts.
public final class SyncProgressHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<SyncProgress?>.Continuation] = [:]
    private var latest: SyncProgress?

    public init() {}

    public func subscribe() -> AsyncStream<SyncProgress?> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let current = latest
            lock.unlock()
            if let current {
                continuation.yield(current)
            }
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    public func emit(_ progress: SyncProgress?) {
        lock.lock()
        latest = progress
        let conts = Array(continuations.values)
        lock.unlock()
        for continuation in conts {
            continuation.yield(progress)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
