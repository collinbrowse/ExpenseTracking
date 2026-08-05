import Foundation
import SwiftData
import CashFlowKit

public actor SwiftDataTagRepository: TagRepository {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func fetchAll() async throws -> [Tag] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<TagEntity>(
            sortBy: [
                SortDescriptor(\.name, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        return try context.fetch(descriptor).map(EntityMappers.tag(from:))
    }

    public func create(name: String) async throws -> Tag {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CashFlowError.persistence(message: "Tag name can't be empty.")
        }
        let id = UUID().uuidString
        let entity = TagEntity(id: id, name: trimmed, createdAt: .now)
        context.insert(entity)
        do {
            try context.save()
        } catch {
            throw CashFlowError.persistence(
                message: "Couldn't save tag. \(error.localizedDescription)"
            )
        }
        // Read back from a fresh context to ensure the store accepted the row.
        let verifyContext = ModelContext(modelContainer)
        let predicate = #Predicate<TagEntity> { $0.id == id }
        var descriptor = FetchDescriptor<TagEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let saved = try verifyContext.fetch(descriptor).first else {
            throw CashFlowError.persistence(message: "Tag failed to persist.")
        }
        return EntityMappers.tag(from: saved)
    }

    public func rename(id: TagID, name: String) async throws {
        let context = ModelContext(modelContainer)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CashFlowError.persistence(message: "Tag name can't be empty.")
        }
        let raw = id.rawValue
        let predicate = #Predicate<TagEntity> { $0.id == raw }
        var descriptor = FetchDescriptor<TagEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else {
            throw CashFlowError.persistence(message: "Tag not found.")
        }
        entity.name = trimmed
        try context.save()
    }

    public func delete(id: TagID) async throws {
        let context = ModelContext(modelContainer)
        let raw = id.rawValue
        let predicate = #Predicate<TagEntity> { $0.id == raw }
        var descriptor = FetchDescriptor<TagEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else { return }
        // Clear memberships before delete so relationship inverses stay consistent.
        entity.transactions = []
        context.delete(entity)
        try Self.stripTagReferences(tagID: id, context: context)
        try context.save()
    }

    /// Removes a deleted tag from rule conditions/actions and transaction suppressions.
    private static func stripTagReferences(tagID: TagID, context: ModelContext) throws {
        let rules = try context.fetch(FetchDescriptor<CategorizationRuleEntity>())
        for rule in rules {
            var conditions = (try? JSONDecoder().decode(
                [CategorizationCondition].self,
                from: rule.conditionsData
            )) ?? []
            let beforeCount = conditions.count
            conditions.removeAll {
                if case .hasTag(let id) = $0 { return id == tagID }
                return false
            }
            if conditions.count != beforeCount {
                rule.conditionsData = try JSONEncoder().encode(conditions)
                if conditions.isEmpty {
                    rule.isEnabled = false
                }
            }
            let tagIDs = EntityMappers.decodeTagIDs(rule.tagIDsData)
            let filtered = tagIDs.filter { $0 != tagID }
            if filtered.count != tagIDs.count {
                rule.tagIDsData = try EntityMappers.encodeTagIDs(filtered)
            }
        }

        let transactions = try context.fetch(FetchDescriptor<TransactionEntity>())
        for transaction in transactions {
            let suppressed = EntityMappers.decodeTagIDs(transaction.suppressedTagIDsData)
            let filtered = suppressed.filter { $0 != tagID }
            if filtered.count != suppressed.count {
                transaction.suppressedTagIDsData = try EntityMappers.encodeTagIDs(filtered)
            }
        }
    }

    /// Used by erase-everything and local wipe — not kept across clear-local.
    public func deleteAll() async throws {
        let context = ModelContext(modelContainer)
        let entities = try context.fetch(FetchDescriptor<TagEntity>())
        for entity in entities {
            entity.transactions = []
            context.delete(entity)
        }
        try context.save()
    }
}
