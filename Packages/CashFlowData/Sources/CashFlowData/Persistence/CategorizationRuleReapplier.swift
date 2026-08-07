import Foundation
import SwiftData
import CashFlowKit

public actor CategorizationRuleReapplier: CategorizationRuleApplying {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func reapplyAllRules() async throws -> Int {
        let context = ModelContext(modelContainer)
        return try reapplyAllRules(context: context)
    }

    public func applyAndCaptureUndo(for rule: CategorizationRule) async throws -> CategorizationRule {
        let context = ModelContext(modelContainer)
        let posted = try context.fetch(
            FetchDescriptor<TransactionEntity>(predicate: #Predicate { !$0.isPending })
        ).map(EntityMappers.transaction(from:))

        let matching = posted.filter {
            CategorizationRuleMatcher.matches(rule, transaction: $0)
        }
        let priors = UndoCategorizationRuleUseCase.priorsToCapture(rule: rule, matching: matching)
        let provisional = CategorizationRuleApplySnapshot(
            appliesCategory: rule.appliesCategory,
            categoryID: rule.categoryID,
            tagIDs: rule.tagIDs,
            renameTitle: rule.renameTitle,
            renameLocation: rule.renameLocation,
            priors: priors
        )
        let withSnapshot = copy(rule, snapshot: provisional.canUndo ? provisional : nil)
        try upsert(withSnapshot, context: context)
        try context.save()

        _ = try reapplyAllRules(context: context)

        let afterByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(
                FetchDescriptor<TransactionEntity>(predicate: #Predicate { !$0.isPending })
            ).map { (TransactionID($0.id), EntityMappers.transaction(from: $0)) }
        )
        let changedPriors = priors.filter { prior in
            guard let after = afterByID[prior.transactionID] else { return false }
            return after.categoryID != prior.categoryID
                || after.userEditedCategory != prior.userEditedCategory
                || after.categorySource != prior.categorySource
                || Set(after.tagIDs) != Set(prior.tagIDs)
                || after.enrichedTitle != prior.enrichedTitle
                || after.enrichedLocation != prior.enrichedLocation
                || after.titleSource != prior.titleSource
        }
        let finalSnapshot = CategorizationRuleApplySnapshot(
            appliesCategory: rule.appliesCategory,
            categoryID: rule.categoryID,
            tagIDs: rule.tagIDs,
            renameTitle: rule.renameTitle,
            renameLocation: rule.renameLocation,
            priors: changedPriors
        )
        let finalRule = copy(rule, snapshot: finalSnapshot.canUndo ? finalSnapshot : nil)
        try upsert(finalRule, context: context)
        try context.save()
        return finalRule
    }

    public func undoRule(id: CategorizationRuleID) async throws -> Int {
        let context = ModelContext(modelContainer)
        let raw = id.rawValue
        let predicate = #Predicate<CategorizationRuleEntity> { $0.id == raw }
        var descriptor = FetchDescriptor<CategorizationRuleEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else { return 0 }
        let rule = try EntityMappers.categorizationRule(from: entity)
        guard let snapshot = rule.applySnapshot, snapshot.canUndo else { return 0 }

        let currentByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<TransactionEntity>())
                .map { (TransactionID($0.id), EntityMappers.transaction(from: $0)) }
        )
        let restorations = UndoCategorizationRuleUseCase.restorations(
            snapshot: snapshot,
            currentByID: currentByID
        )

        let tagsByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<TagEntity>()).map { ($0.id, $0) }
        )
        var touched = Set<TransactionID>()

        for assignment in restorations.categoryAssignments {
            let tid = assignment.transactionID.rawValue
            let pred = #Predicate<TransactionEntity> { $0.id == tid }
            var desc = FetchDescriptor<TransactionEntity>(predicate: pred)
            desc.fetchLimit = 1
            guard let tx = try context.fetch(desc).first else { continue }
            tx.categoryID = assignment.categoryID.rawValue
            tx.userEditedCategory = assignment.userEditedCategory
            tx.categorySourceRaw = EntityMappers.categorySourceRaw(from: assignment.categorySource)
            touched.insert(assignment.transactionID)
        }
        for assignment in restorations.tagAssignments {
            let tid = assignment.transactionID.rawValue
            let pred = #Predicate<TransactionEntity> { $0.id == tid }
            var desc = FetchDescriptor<TransactionEntity>(predicate: pred)
            desc.fetchLimit = 1
            guard let tx = try context.fetch(desc).first else { continue }
            tx.tags = assignment.tagIDs.compactMap { tagsByID[$0.rawValue] }
            if let suppressed = assignment.suppressedTagIDs {
                tx.suppressedTagIDsData = try EntityMappers.encodeTagIDs(suppressed)
            }
            touched.insert(assignment.transactionID)
        }
        for assignment in restorations.titleLocationAssignments {
            let tid = assignment.transactionID.rawValue
            let pred = #Predicate<TransactionEntity> { $0.id == tid }
            var desc = FetchDescriptor<TransactionEntity>(predicate: pred)
            desc.fetchLimit = 1
            guard let tx = try context.fetch(desc).first else { continue }
            tx.enrichedTitle = assignment.title
            tx.enrichedLocation = assignment.location
            tx.titleSourceRaw = EntityMappers.titleSourceRaw(from: assignment.titleSource)
            touched.insert(assignment.transactionID)
        }
        let restored = touched.count

        entity.isEnabled = false
        entity.applySnapshotData = nil
        try context.save()

        _ = try reapplyAllRules(context: context)
        return restored
    }

    private func reapplyAllRules(context: ModelContext) throws -> Int {
        let ruleEntities = try context.fetch(
            FetchDescriptor<CategorizationRuleEntity>(
                sortBy: [
                    SortDescriptor(\.priority, order: .forward),
                    SortDescriptor(\.id, order: .forward),
                ]
            )
        )
        let knownTagIDs = Set(
            try context.fetch(FetchDescriptor<TagEntity>()).map { TagID($0.id) }
        )
        let rules = try ruleEntities.map { try EntityMappers.categorizationRule(from: $0) }
            .map { Self.sanitizedRule($0, knownTagIDs: knownTagIDs) }

        let txDescriptor = FetchDescriptor<TransactionEntity>(
            predicate: #Predicate { !$0.isPending }
        )
        let transactions = try context.fetch(txDescriptor)
        let tagsByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<TagEntity>()).map { ($0.id, $0) }
        )

        var changed = 0
        for entity in transactions {
            let current = EntityMappers.transaction(from: entity)
            let resolved = ResolveTransactionCategoryUseCase.execute(
                transaction: current,
                rules: rules,
                categoryLocked: current.categoryLocked,
                currentCategoryID: current.categoryID,
                fallbackCategoryID: current.categoryID
            )

            let newTagIDs = ResolveTransactionCategoryUseCase.applyingTags(
                current: current.tagIDs,
                ruleTags: resolved.tagIDsToAdd,
                suppressed: current.suppressedTagIDs
            )

            var didChange = false
            if !current.categoryLocked, resolved.matchedCategoryRule {
                if entity.categoryID != resolved.categoryID.rawValue
                    || entity.userEditedCategory != true
                    || entity.categorySourceRaw != CategorySource.rule.rawValue
                {
                    entity.categoryID = resolved.categoryID.rawValue
                    entity.userEditedCategory = true
                    entity.categorySourceRaw = CategorySource.rule.rawValue
                    didChange = true
                }
            }

            if resolved.hasRename,
               TitleSource.canOverwrite(existing: current.titleSource, with: .rule)
            {
                let newTitle = resolved.renameTitle ?? current.enrichedTitle ?? current.displayTitle
                let newLocation = resolved.renameLocation ?? current.enrichedLocation
                if entity.enrichedTitle != newTitle
                    || entity.enrichedLocation != newLocation
                    || entity.titleSourceRaw != TitleSource.rule.rawValue
                {
                    entity.enrichedTitle = newTitle
                    if resolved.renameLocation != nil {
                        entity.enrichedLocation = resolved.renameLocation
                    } else if entity.enrichedLocation == nil {
                        entity.enrichedLocation = newLocation
                    }
                    entity.titleSourceRaw = TitleSource.rule.rawValue
                    didChange = true
                }
            }

            if Set(newTagIDs.map(\.rawValue)) != Set(current.tagIDs.map(\.rawValue)) {
                entity.tags = newTagIDs.compactMap { tagsByID[$0.rawValue] }
                didChange = true
            }
            if didChange {
                changed += 1
            }
        }
        try context.save()
        return changed
    }

    private func upsert(_ rule: CategorizationRule, context: ModelContext) throws {
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
    }

    private func copy(
        _ rule: CategorizationRule,
        snapshot: CategorizationRuleApplySnapshot?
    ) -> CategorizationRule {
        CategorizationRule(
            id: rule.id,
            categoryID: rule.categoryID,
            priority: rule.priority,
            isEnabled: rule.isEnabled,
            conditions: rule.conditions,
            renameTitle: rule.renameTitle,
            renameLocation: rule.renameLocation,
            appliesCategory: rule.appliesCategory,
            tagIDs: rule.tagIDs,
            createdByAssistant: rule.createdByAssistant,
            applySnapshot: snapshot
        )
    }

    private static func sanitizedRule(
        _ rule: CategorizationRule,
        knownTagIDs: Set<TagID>
    ) -> CategorizationRule {
        let conditions = rule.conditions.compactMap { condition -> CategorizationCondition? in
            switch condition {
            case .hasTag(let id):
                return knownTagIDs.contains(id) ? condition : nil
            default:
                return condition
            }
        }
        let tagIDs = rule.tagIDs.filter { knownTagIDs.contains($0) }
        return CategorizationRule(
            id: rule.id,
            categoryID: rule.categoryID,
            priority: rule.priority,
            isEnabled: rule.isEnabled && !conditions.isEmpty,
            conditions: conditions,
            renameTitle: rule.renameTitle,
            renameLocation: rule.renameLocation,
            appliesCategory: rule.appliesCategory,
            tagIDs: tagIDs,
            createdByAssistant: rule.createdByAssistant,
            applySnapshot: rule.applySnapshot
        )
    }
}
