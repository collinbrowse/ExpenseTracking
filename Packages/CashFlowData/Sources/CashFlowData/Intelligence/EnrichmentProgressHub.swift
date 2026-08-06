import Foundation
import CashFlowKit

/// Fan-out hub for title-cleanup progress (Settings UI + Live Activity mirror).
public final class EnrichmentProgressHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<EnrichmentProgress?>.Continuation] = [:]
    private var latest: EnrichmentProgress?

    public init() {}

    public var current: EnrichmentProgress? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    public func subscribe() -> AsyncStream<EnrichmentProgress?> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let current = latest
            lock.unlock()
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                self?.remove(id)
            }
        }
    }

    public func emit(_ progress: EnrichmentProgress?) {
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
