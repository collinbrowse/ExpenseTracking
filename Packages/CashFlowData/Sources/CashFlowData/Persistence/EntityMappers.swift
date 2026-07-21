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
            balanceDate: entity.balanceDate
        )
    }

    static func transaction(from entity: TransactionEntity) -> Transaction {
        let resolvedAccountID = entity.account?.id ?? entity.accountID
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
            categoryLocked: entity.categoryLocked
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
            appliesCategory: entity.appliesCategory
        )
    }

    static func encodeConditions(_ conditions: [CategorizationCondition]) throws -> Data {
        try JSONEncoder().encode(conditions)
    }
}
