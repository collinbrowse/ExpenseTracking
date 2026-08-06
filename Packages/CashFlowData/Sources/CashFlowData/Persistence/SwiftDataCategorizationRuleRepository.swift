import Foundation
import SwiftData
import CashFlowKit

public actor SwiftDataCategorizationRuleRepository: CategorizationRuleRepository {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func fetchAll() async throws -> [CategorizationRule] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CategorizationRuleEntity>(
            sortBy: [
                SortDescriptor(\.priority, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        return try context.fetch(descriptor).map { try EntityMappers.categorizationRule(from: $0) }
    }

    public func upsert(_ rule: CategorizationRule) async throws {
        let context = ModelContext(modelContainer)
        let id = rule.id.rawValue
        let predicate = #Predicate<CategorizationRuleEntity> { $0.id == id }
        var descriptor = FetchDescriptor<CategorizationRuleEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        let data = try EntityMappers.encodeConditions(rule.conditions)
        let tagData = try EntityMappers.encodeTagIDs(rule.tagIDs)
        let snapshotData = try EntityMappers.encodeApplySnapshot(rule.applySnapshot)

        if let existing = try context.fetch(descriptor).first {
            existing.categoryID = rule.categoryID.rawValue
            existing.priority = rule.priority
            existing.isEnabled = rule.isEnabled
            existing.conditionsData = data
            existing.renameTitle = rule.renameTitle
            existing.renameLocation = rule.renameLocation
            existing.appliesCategory = rule.appliesCategory
            existing.tagIDsData = tagData
            // Preserve provenance when editing an assistant-created rule.
            existing.createdByAssistant = existing.createdByAssistant || rule.createdByAssistant
            existing.applySnapshotData = snapshotData
        } else {
            context.insert(
                CategorizationRuleEntity(
                    id: id,
                    categoryID: rule.categoryID.rawValue,
                    priority: rule.priority,
                    isEnabled: rule.isEnabled,
                    conditionsData: data,
                    renameTitle: rule.renameTitle,
                    renameLocation: rule.renameLocation,
                    appliesCategory: rule.appliesCategory,
                    tagIDsData: tagData,
                    createdByAssistant: rule.createdByAssistant,
                    applySnapshotData: snapshotData
                )
            )
        }
        try context.save()
    }

    public func delete(id: CategorizationRuleID) async throws {
        let context = ModelContext(modelContainer)
        let raw = id.rawValue
        let predicate = #Predicate<CategorizationRuleEntity> { $0.id == raw }
        var descriptor = FetchDescriptor<CategorizationRuleEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else { return }
        context.delete(entity)
        try context.save()
    }

    public func reorder(ids: [CategorizationRuleID]) async throws {
        let context = ModelContext(modelContainer)
        let entities = try context.fetch(FetchDescriptor<CategorizationRuleEntity>())
        let byID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        for (index, id) in ids.enumerated() {
            byID[id.rawValue]?.priority = index
        }
        try context.save()
    }

    /// Used by erase-everything only — not clear-local-data.
    public func deleteAll() async throws {
        let context = ModelContext(modelContainer)
        let entities = try context.fetch(FetchDescriptor<CategorizationRuleEntity>())
        for entity in entities {
            context.delete(entity)
        }
        try context.save()
    }
}
