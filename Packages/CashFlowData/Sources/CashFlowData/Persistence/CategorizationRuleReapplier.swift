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
        let ruleEntities = try context.fetch(
            FetchDescriptor<CategorizationRuleEntity>(
                sortBy: [
                    SortDescriptor(\.priority, order: .forward),
                    SortDescriptor(\.id, order: .forward),
                ]
            )
        )
        let rules = try ruleEntities.map { try EntityMappers.categorizationRule(from: $0) }

        let txDescriptor = FetchDescriptor<TransactionEntity>(
            predicate: #Predicate { !$0.isPending }
        )
        let transactions = try context.fetch(txDescriptor)

        var changed = 0
        for entity in transactions {
            let current = EntityMappers.transaction(from: entity)
            let resolved = ResolveTransactionCategoryUseCase.execute(
                description: current.description,
                amount: current.amount,
                accountID: current.accountID,
                rules: rules,
                categoryLocked: current.categoryLocked,
                currentCategoryID: current.categoryID,
                // Keep the current category when nothing matches — never re-run the
                // built-in suggester during reapply (that would wipe manual edits).
                fallbackCategoryID: current.categoryID
            )
            let newDescription: String
            if let renameTitle = resolved.renameTitle {
                newDescription = ResolveTransactionCategoryUseCase.applyingRename(
                    to: current.description,
                    renameTitle: renameTitle
                )
            } else {
                newDescription = current.description
            }

            var didChange = false
            // Only rewrite category when a user rule matched. Non-matching rows keep
            // whatever category / userEditedCategory they already have.
            if !current.categoryLocked, resolved.matchedUserRule {
                if entity.categoryID != resolved.categoryID.rawValue
                    || entity.userEditedCategory != true
                {
                    entity.categoryID = resolved.categoryID.rawValue
                    entity.userEditedCategory = true
                    didChange = true
                }
            }
            if entity.transactionDescription != newDescription {
                entity.transactionDescription = newDescription
                didChange = true
            }
            if didChange {
                changed += 1
            }
        }
        try context.save()
        return changed
    }
}
