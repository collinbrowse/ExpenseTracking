import Foundation

/// Turns natural language into a draft that matches the manual rule editor fields.
public protocol CategorizationRuleDrafting: Sendable {
    func draft(from prompt: String, accounts: [Account]) async throws -> CategorizationRuleDraft
}
