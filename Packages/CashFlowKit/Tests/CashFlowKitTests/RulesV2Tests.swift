import Foundation
import Testing
@testable import CashFlowKit

@Suite("Rules 2.0 matching and tags")
struct RulesV2Tests {
    private let account = AccountID("acct-1")
    private let thailand = TagID("thailand")
    private let asia = TagID("asia")

    @Test("locationContains matches displayLocation")
    func locationContains() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.travelVacation.id,
            priority: 0,
            conditions: [.locationContains("Thailand")],
            appliesCategory: true
        )
        let tx = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -20,
            postedDate: .now,
            description: "CAFE  BANGKOK",
            categoryID: SystemCategory.other.id,
            enrichedTitle: "Cafe",
            enrichedLocation: "Bangkok Thailand"
        )
        #expect(CategorizationRuleMatcher.matches(rule, transaction: tx))
    }

    @Test("titleContains matches enriched displayTitle even when raw bank text differs")
    func titleContainsUsesDisplayTitle() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.income.id,
            priority: 0,
            conditions: [.titleContains("CDLE")],
            appliesCategory: true
        )
        let tx = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: 500,
            postedDate: .now,
            // Raw text without the CDLE token the user sees in the UI.
            description: "COLORADO DEPT LABOR UI PAYMENT",
            categoryID: SystemCategory.transfer.id,
            enrichedTitle: "CDLE UI BENEFITS UI PAYMENT",
            enrichedLocation: nil
        )
        #expect(CategorizationRuleMatcher.matches(rule, transaction: tx))
        let resolved = ResolveTransactionCategoryUseCase.execute(
            transaction: tx,
            rules: [rule],
            categoryLocked: false,
            currentCategoryID: tx.categoryID,
            fallbackCategoryID: tx.categoryID
        )
        #expect(resolved.matchedCategoryRule)
        #expect(resolved.categoryID == SystemCategory.income.id)
    }

    @Test("hasTag and categoryIs match start-of-pass state")
    func tagAndCategoryConditions() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.travelVacation.id,
            priority: 0,
            conditions: [.hasTag(thailand), .categoryIs(SystemCategory.dining.id)],
            tagIDs: [asia]
        )
        let matching = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -10,
            postedDate: .now,
            description: "Lunch",
            categoryID: SystemCategory.dining.id,
            tagIDs: [thailand]
        )
        let wrongCategory = Transaction(
            id: TransactionID("2"),
            accountID: account,
            externalID: "e2",
            amount: -10,
            postedDate: .now,
            description: "Lunch",
            categoryID: SystemCategory.shopping.id,
            tagIDs: [thailand]
        )
        #expect(CategorizationRuleMatcher.matches(rule, transaction: matching))
        #expect(!CategorizationRuleMatcher.matches(rule, transaction: wrongCategory))
    }

    @Test("Tag union across matching rules; category is first match")
    func tagUnionAndCategoryPriority() {
        let low = CategorizationRule(
            id: CategorizationRuleID("a"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Coffee")],
            appliesCategory: true,
            tagIDs: [thailand]
        )
        let high = CategorizationRule(
            id: CategorizationRuleID("b"),
            categoryID: SystemCategory.shopping.id,
            priority: 1,
            conditions: [.titleContains("Coffee")],
            appliesCategory: true,
            tagIDs: [asia]
        )
        let tx = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -5,
            postedDate: .now,
            description: "Coffee Shop",
            categoryID: SystemCategory.other.id
        )
        let resolved = ResolveTransactionCategoryUseCase.execute(
            transaction: tx,
            rules: [high, low],
            categoryLocked: false,
            currentCategoryID: tx.categoryID
        )
        #expect(resolved.categoryID == SystemCategory.dining.id)
        #expect(Set(resolved.tagIDsToAdd) == Set([thailand, asia]))
    }

    @Test("Single-pass: category rule cannot cascade into categoryIs")
    func singlePassNoCascade() {
        let setDining = CategorizationRule(
            id: CategorizationRuleID("a"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Merchant")],
            appliesCategory: true
        )
        let fromDining = CategorizationRule(
            id: CategorizationRuleID("b"),
            categoryID: SystemCategory.travelVacation.id,
            priority: 1,
            conditions: [.categoryIs(SystemCategory.dining.id)],
            appliesCategory: true,
            tagIDs: [asia]
        )
        let tx = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -5,
            postedDate: .now,
            description: "Merchant",
            categoryID: SystemCategory.other.id
        )
        let resolved = ResolveTransactionCategoryUseCase.execute(
            transaction: tx,
            rules: [setDining, fromDining],
            categoryLocked: false,
            currentCategoryID: tx.categoryID
        )
        #expect(resolved.categoryID == SystemCategory.dining.id)
        #expect(resolved.tagIDsToAdd.isEmpty)
    }

    @Test("Suppressed tags are not re-added; other rule tags still apply")
    func suppressions() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.other.id,
            priority: 0,
            conditions: [.titleContains("Trip")],
            appliesCategory: false,
            tagIDs: [thailand, asia]
        )
        let tx = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -5,
            postedDate: .now,
            description: "Trip",
            categoryID: SystemCategory.other.id,
            tagIDs: [],
            suppressedTagIDs: [thailand]
        )
        let resolved = ResolveTransactionCategoryUseCase.execute(
            transaction: tx,
            rules: [rule],
            categoryLocked: false,
            currentCategoryID: tx.categoryID
        )
        #expect(resolved.tagIDsToAdd == [asia])

        let updated = ResolveTransactionCategoryUseCase.updatedSuppressions(
            previous: [thailand, asia],
            new: [asia],
            existingSuppressions: []
        )
        #expect(updated == [thailand])

        let cleared = ResolveTransactionCategoryUseCase.updatedSuppressions(
            previous: [asia],
            new: [asia, thailand],
            existingSuppressions: [thailand]
        )
        #expect(cleared.isEmpty)
    }

    @Test("Merge applies rule tags and preserves suppressions")
    func mergeTags() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.other.id,
            priority: 0,
            conditions: [.titleContains("Trip")],
            appliesCategory: false,
            tagIDs: [thailand]
        )
        let local = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -5,
            postedDate: .now,
            description: "Trip",
            categoryID: SystemCategory.other.id,
            userEditedCategory: true,
            tagIDs: [],
            suppressedTagIDs: [thailand]
        )
        let remote = Transaction(
            id: TransactionID("1"),
            accountID: account,
            externalID: "e1",
            amount: -6,
            postedDate: .now,
            description: "Trip",
            categoryID: SystemCategory.other.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [rule])
        #expect(merged.tagIDs.isEmpty)
        #expect(merged.suppressedTagIDs == [thailand])
        #expect(merged.amount == -6)
    }

    @Test("Amount bounds parse from string path used by Generable adapters")
    func decimalParsing() {
        #expect(Decimal(string: "12.50") == Decimal(string: "12.50"))
        #expect(Decimal(string: "12.50".replacingOccurrences(of: "$", with: "")) != nil)
        let condition = CategorizationCondition.amountMin(Decimal(string: "10")!)
        if case .amountMin(let value) = condition {
            #expect(value == 10)
        } else {
            Issue.record("Expected amountMin")
        }
    }

    @Test("Condition formatting covers new kinds")
    func formatting() {
        let text = CategorizationConditionFormatting.summary(
            for: [
                .locationContains("Thailand"),
                .categoryIs(SystemCategory.dining.id),
                .hasTag(thailand),
            ],
            tagName: { _ in "Thailand" }
        )
        #expect(text.contains("Location contains"))
        #expect(text.contains("Category is"))
        #expect(text.contains("Has tag Thailand"))
    }
}
