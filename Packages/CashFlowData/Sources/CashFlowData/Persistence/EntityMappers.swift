import Foundation
import CashFlowKit

enum EntityMappers {
    static func account(from entity: AccountEntity) -> Account {
        Account(
            id: AccountID(entity.id),
            externalID: entity.externalID,
            name: entity.name,
            institutionName: entity.institutionName,
            currencyCode: entity.currencyCode,
            balance: entity.balance,
            balanceDate: entity.balanceDate,
            syncIssue: entity.syncIssue
        )
    }

    static func transaction(from entity: TransactionEntity) -> Transaction {
        let resolvedAccountID = entity.account?.id ?? entity.accountID
        let tagIDs = entity.tags.map { TagID($0.id) }.sorted { $0.rawValue < $1.rawValue }
        let suppressed = decodeTagIDs(entity.suppressedTagIDsData)
        return Transaction(
            id: TransactionID(entity.id),
            accountID: AccountID(resolvedAccountID),
            externalID: entity.externalID,
            amount: entity.amount,
            postedDate: entity.postedDate,
            description: entity.transactionDescription,
            categoryID: CategoryID(entity.categoryID),
            currencyCode: entity.currencyCode,
            userEditedCategory: entity.userEditedCategory,
            isPending: entity.isPending,
            categoryLocked: entity.categoryLocked,
            tagIDs: tagIDs,
            suppressedTagIDs: suppressed,
            enrichedTitle: entity.enrichedTitle,
            enrichedLocation: entity.enrichedLocation,
            titleSource: titleSource(from: entity.titleSourceRaw)
        )
    }

    static func tag(from entity: TagEntity) -> Tag {
        Tag(
            id: TagID(entity.id),
            name: entity.name,
            createdAt: entity.createdAt
        )
    }

    static func categorizationRule(from entity: CategorizationRuleEntity) throws -> CategorizationRule {
        let conditions = try JSONDecoder().decode(
            [CategorizationCondition].self,
            from: entity.conditionsData
        )
        return CategorizationRule(
            id: CategorizationRuleID(entity.id),
            categoryID: CategoryID(entity.categoryID),
            priority: entity.priority,
            isEnabled: entity.isEnabled,
            conditions: conditions,
            renameTitle: entity.renameTitle,
            renameLocation: entity.renameLocation,
            appliesCategory: entity.appliesCategory,
            tagIDs: decodeTagIDs(entity.tagIDsData),
            createdByAssistant: entity.createdByAssistant,
            applySnapshot: decodeApplySnapshot(entity.applySnapshotData)
        )
    }

    static func encodeConditions(_ conditions: [CategorizationCondition]) throws -> Data {
        try JSONEncoder().encode(conditions)
    }

    static func encodeTagIDs(_ tagIDs: [TagID]) throws -> Data? {
        guard !tagIDs.isEmpty else { return nil }
        return try JSONEncoder().encode(tagIDs)
    }

    static func decodeTagIDs(_ data: Data?) -> [TagID] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([TagID].self, from: data)) ?? []
    }

    static func encodeApplySnapshot(_ snapshot: CategorizationRuleApplySnapshot?) throws -> Data? {
        guard let snapshot, snapshot.canUndo else { return nil }
        return try JSONEncoder().encode(snapshot)
    }

    static func decodeApplySnapshot(_ data: Data?) -> CategorizationRuleApplySnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CategorizationRuleApplySnapshot.self, from: data)
    }

    static func titleSource(from raw: String?) -> TitleSource? {
        guard let raw else { return nil }
        return TitleSource(rawValue: raw)
    }

    static func titleSourceRaw(from source: TitleSource?) -> String? {
        source?.rawValue
    }
}
