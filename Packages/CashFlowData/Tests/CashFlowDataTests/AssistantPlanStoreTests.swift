import Testing
import Foundation
import CashFlowKit
@testable import CashFlowData

@Suite("AssistantActionStore")
struct AssistantPlanStoreTests {
    @Test("Commits undo snapshot")
    func commitsUndo() async {
        let store = AssistantActionStore()
        let snapshot = AssistantUndoSnapshot(
            previousTagAssignments: [
                TagAssignment(transactionID: TransactionID("1"), tagIDs: []),
                TagAssignment(transactionID: TransactionID("2"), tagIDs: [TagID("old")]),
            ],
            previousCategoryAssignments: [
                CategoryAssignment(
                    transactionID: TransactionID("1"),
                    categoryID: SystemCategory.other.id,
                    userEditedCategory: false
                ),
            ],
            ruleIDToDisable: CategorizationRuleID("r1"),
            summary: "Thailand trip tagging"
        )
        await store.commit(snapshot)
        #expect(await store.lastUndoSnapshot()?.affectedTransactionCount == 2)
        #expect(await store.lastUndoSnapshot()?.ruleIDToDisable == CategorizationRuleID("r1"))
        #expect(await store.lastUndoSnapshot()?.summary == "Thailand trip tagging")
    }
}
