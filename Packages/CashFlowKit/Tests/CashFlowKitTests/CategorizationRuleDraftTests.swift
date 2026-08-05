import Testing
import Foundation
@testable import CashFlowKit

@Suite("CategorizationRuleDraft")
struct CategorizationRuleDraftTests {
    @Test("makeRule matches manual categorize shape")
    func categorizeShape() {
        let draft = CategorizationRuleDraft(
            action: .categorize,
            categoryID: SystemCategory.dining.id,
            conditions: [.titleContains("Starbucks")]
        )
        let rule = draft.makeRule(id: CategorizationRuleID("r1"), priority: 3)
        #expect(rule.appliesCategory == true)
        #expect(rule.renameTitle == nil)
        #expect(rule.categoryID == SystemCategory.dining.id)
        #expect(rule.conditions == [.titleContains("Starbucks")])
        #expect(rule.priority == 3)
    }

    @Test("makeRule matches manual rename shape")
    func renameShape() {
        let draft = CategorizationRuleDraft(
            action: .rename,
            categoryID: SystemCategory.other.id,
            renameTitle: "Starbucks",
            conditions: [.descriptionContains("SBUX")]
        )
        let rule = draft.makeRule(priority: 0)
        #expect(rule.appliesCategory == false)
        #expect(rule.renameTitle == "Starbucks")
        #expect(rule.conditions == [.descriptionContains("SBUX")])
    }
}
