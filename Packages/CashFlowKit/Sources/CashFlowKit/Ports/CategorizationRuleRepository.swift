import Foundation

public protocol CategorizationRuleRepository: Sendable {
    /// Enabled and disabled rules, ascending priority.
    func fetchAll() async throws -> [CategorizationRule]

    func upsert(_ rule: CategorizationRule) async throws

    func delete(id: CategorizationRuleID) async throws

    /// Reassigns priorities 0..<n in the given order (first = highest priority).
    func reorder(ids: [CategorizationRuleID]) async throws
}

/// Store-wide re-apply after rule CRUD. Not for list UI pagination.
public protocol CategorizationRuleApplying: Sendable {
    /// Re-resolves categories for all unlocked transactions. Returns how many categories changed.
    func reapplyAllRules() async throws -> Int
}
