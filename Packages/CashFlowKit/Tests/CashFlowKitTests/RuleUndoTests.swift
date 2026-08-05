import Foundation
import Testing
@testable import CashFlowKit

@Suite("UndoCategorizationRuleUseCase")
struct RuleUndoTests {
    private let account = AccountID("acct-1")
    private let trip = TagID("trip")
    private let personal = TagID("personal")

    @Test("Restores category and tags the rule applied")
    func restoresRuleEffects() {
        let prior = CategorizationRuleTransactionPrior(
            transactionID: TransactionID("1"),
            categoryID: SystemCategory.other.id,
            userEditedCategory: false,
            tagIDs: [],
            description: "CAFE BANGKOK"
        )
        let snapshot = CategorizationRuleApplySnapshot(
            appliesCategory: true,
            categoryID: SystemCategory.dining.id,
            tagIDs: [trip],
            renameTitle: nil,
            priors: [prior]
        )
        let current = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -12,
            postedDate: .now,
            description: "CAFE BANGKOK",
            categoryID: SystemCategory.dining.id,
            userEditedCategory: true,
            tagIDs: [trip]
        )

        let restorations = UndoCategorizationRuleUseCase.restorations(
            snapshot: snapshot,
            currentByID: [current.id: current]
        )
        #expect(restorations.categoryAssignments.count == 1)
        #expect(restorations.categoryAssignments[0].categoryID == SystemCategory.other.id)
        #expect(restorations.tagAssignments.count == 1)
        #expect(restorations.tagAssignments[0].tagIDs.isEmpty)
    }

    @Test("Manual category change wins over undo")
    func manualCategoryWins() {
        let prior = CategorizationRuleTransactionPrior(
            transactionID: TransactionID("1"),
            categoryID: SystemCategory.other.id,
            userEditedCategory: false,
            tagIDs: [],
            description: "CAFE"
        )
        let snapshot = CategorizationRuleApplySnapshot(
            appliesCategory: true,
            categoryID: SystemCategory.dining.id,
            tagIDs: [],
            renameTitle: nil,
            priors: [prior]
        )
        let current = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -12,
            postedDate: .now,
            description: "CAFE",
            categoryID: SystemCategory.shopping.id,
            userEditedCategory: true
        )

        let restorations = UndoCategorizationRuleUseCase.restorations(
            snapshot: snapshot,
            currentByID: [current.id: current]
        )
        #expect(restorations.categoryAssignments.isEmpty)
    }

    @Test("Manual tag removal wins; keeps unrelated tags")
    func manualTagRemovalWins() {
        let prior = CategorizationRuleTransactionPrior(
            transactionID: TransactionID("1"),
            categoryID: SystemCategory.other.id,
            userEditedCategory: false,
            tagIDs: [personal],
            description: "CAFE"
        )
        let snapshot = CategorizationRuleApplySnapshot(
            appliesCategory: false,
            categoryID: SystemCategory.other.id,
            tagIDs: [trip],
            renameTitle: nil,
            priors: [prior]
        )
        // User removed trip and kept personal (plus maybe nothing else).
        let current = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -12,
            postedDate: .now,
            description: "CAFE",
            categoryID: SystemCategory.other.id,
            tagIDs: [personal],
            suppressedTagIDs: [trip]
        )

        let restorations = UndoCategorizationRuleUseCase.restorations(
            snapshot: snapshot,
            currentByID: [current.id: current]
        )
        #expect(restorations.tagAssignments.isEmpty)
    }

    @Test("priorsToCapture skips transactions the rule would not change")
    func priorsSkipUnchanged() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Cafe")],
            appliesCategory: true,
            tagIDs: [trip]
        )
        let alreadyApplied = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -12,
            postedDate: .now,
            description: "Cafe",
            categoryID: SystemCategory.dining.id,
            userEditedCategory: true,
            tagIDs: [trip]
        )
        let needsChange = Transaction(
            id: TransactionID("2"),
            accountID: account,
            externalID: "e2",
            amount: -8,
            postedDate: .now,
            description: "Cafe 2",
            categoryID: SystemCategory.other.id,
            tagIDs: []
        )

        let priors = UndoCategorizationRuleUseCase.priorsToCapture(
            rule: rule,
            matching: [alreadyApplied, needsChange]
        )
        #expect(priors.map(\.transactionID) == [TransactionID("2")])
    }
}
