import Foundation
import Testing
@testable import CashFlowKit

@Suite("CategorizationRuleFormatting")
struct CategorizationRuleFormattingTests {
    @Test("Categorize rule describes condition and category action")
    func categorize() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.income.id,
            priority: 0,
            conditions: [.titleContains("Mobile Deposit")],
            appliesCategory: true
        )
        #expect(
            CategorizationRuleFormatting.summary(for: rule)
                == "Title contains “Mobile Deposit”\nCategory set as Income"
        )
    }

    @Test("Rename-only rule describes rename action")
    func renameOnly() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.other.id,
            priority: 0,
            conditions: [.titleContains("STARBUCKS")],
            renameTitle: "Starbucks",
            appliesCategory: false
        )
        #expect(
            CategorizationRuleFormatting.summary(for: rule)
                == "Title contains “STARBUCKS”\nRename title to “Starbucks”"
        )
    }

    @Test("Tag-only rule uses singular or plural tag wording")
    func tags() {
        let trip = TagID("trip")
        let asia = TagID("asia")
        let one = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.other.id,
            priority: 0,
            conditions: [.locationContains("Thailand")],
            appliesCategory: false,
            tagIDs: [trip]
        )
        #expect(
            CategorizationRuleFormatting.summary(for: one, tagName: { _ in "Trip" })
                == "Location contains “Thailand”\nAdd tag Trip"
        )

        let many = CategorizationRule(
            id: CategorizationRuleID("r2"),
            categoryID: SystemCategory.other.id,
            priority: 0,
            conditions: [.locationContains("Thailand")],
            appliesCategory: false,
            tagIDs: [trip, asia]
        )
        #expect(
            CategorizationRuleFormatting.summary(
                for: many,
                tagName: { $0 == trip ? "Trip" : "Asia" }
            ) == "Location contains “Thailand”\nAdd tags Trip, Asia"
        )
    }

    @Test("Combined category rename and tags put each action on its own line")
    func combined() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Cafe"), .amountMin(10)],
            renameTitle: "Cafe",
            appliesCategory: true,
            tagIDs: [TagID("coffee")]
        )
        #expect(
            CategorizationRuleFormatting.summary(for: rule, tagName: { _ in "Coffee" })
                == "Title contains “Cafe” · Amount ≥ $10.00\nCategory set as Food & Dining\nRename title to “Cafe”\nAdd tag Coffee"
        )
    }
}
