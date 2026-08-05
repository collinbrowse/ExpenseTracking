import Foundation
import CashFlowKit

/// Tracks undo snapshots for applied assistant mutations.
public actor AssistantActionStore {
    private var lastUndo: AssistantUndoSnapshot?

    public init() {}

    public func commit(_ snapshot: AssistantUndoSnapshot) {
        lastUndo = snapshot.isEmpty ? nil : snapshot
    }

    public func lastUndoSnapshot() -> AssistantUndoSnapshot? {
        lastUndo
    }

    public func discardUndo() {
        lastUndo = nil
    }
}

/// Back-compat alias used by older call sites / tests.
public typealias AssistantPlanStore = AssistantActionStore
