import Foundation

public protocol TagRepository: Sendable {
    func fetchAll() async throws -> [Tag]

    /// Creates a tag with a trimmed non-empty name. Returns the persisted tag.
    func create(name: String) async throws -> Tag

    func rename(id: TagID, name: String) async throws

    /// Deletes the tag and removes it from all transactions.
    func delete(id: TagID) async throws
}
