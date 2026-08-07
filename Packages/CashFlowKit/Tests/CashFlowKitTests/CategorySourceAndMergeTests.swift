import Testing
import Foundation
@testable import CashFlowKit

@Suite("CategorySource precedence")
struct CategorySourcePrecedenceTests {
    @Test("Ranked overwrite rules (rule > user > llm > keyword)")
    func canOverwrite() {
        #expect(CategorySource.canOverwrite(existing: .user, with: .llm) == false)
        #expect(CategorySource.canOverwrite(existing: .user, with: .rule) == true)
        #expect(CategorySource.canOverwrite(existing: .rule, with: .user) == false)
        #expect(CategorySource.canOverwrite(existing: .llm, with: .rule) == true)
        #expect(CategorySource.canOverwrite(existing: .keyword, with: .llm) == true)
        #expect(CategorySource.canOverwrite(existing: nil, with: .llm) == true)
        #expect(CategorySource.canOverwrite(existing: .llm, with: .keyword) == false)
    }
}

@Suite("MergeSyncPolicy AI-first categories")
struct MergeAICategoryTests {
    private let account = AccountID("a1")

    @Test("New remote without rule starts Undefined")
    func newRemoteUndefined() {
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "STARBUCKS",
            categoryID: SystemCategory.dining.id
        )
        let merged = MergeSyncPolicy.merge(local: nil, remote: remote, rules: [])
        #expect(merged.categoryID == SystemCategory.undefined.id)
        #expect(merged.categorySource == nil)
        #expect(merged.userEditedCategory == false)
    }

    @Test("LLM category sticks across same-description re-sync")
    func llmSticksOnResync() {
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "STARBUCKS",
            categoryID: SystemCategory.dining.id,
            categorySource: .llm
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -15,
            postedDate: .now,
            description: "STARBUCKS",
            categoryID: SystemCategory.groceries.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [])
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.categorySource == .llm)
        #expect(merged.amount == -15)
    }

    @Test("User edit sticks even when bank description changes")
    func userSticksOnDescriptionChange() {
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "OLD MERCHANT",
            categoryID: SystemCategory.dining.id,
            userEditedCategory: true,
            categorySource: .user
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "NEW MERCHANT",
            categoryID: SystemCategory.shopping.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [])
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.categorySource == .user)
        #expect(merged.userEditedCategory == true)
        #expect(merged.description == "NEW MERCHANT")
    }

    @Test("LLM category resets to Undefined when bank description changes")
    func llmResetsOnDescriptionChange() {
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "OLD MERCHANT",
            categoryID: SystemCategory.dining.id,
            categorySource: .llm
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "NEW MERCHANT",
            categoryID: SystemCategory.shopping.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [])
        #expect(merged.categoryID == SystemCategory.undefined.id)
        #expect(merged.categorySource == nil)
    }

    @Test("Undefined display name")
    func undefinedName() {
        #expect(SystemCategory.undefined.name == "Undefined")
        #expect(SystemCategory.undefined.kind == .expense)
    }

    @Test("preferSuggestedCategory stamps Demo seeds as keyword")
    func preferSuggestedCategory() {
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 3_200,
            postedDate: .now,
            description: "Payroll ACME Corp",
            categoryID: SystemCategory.income.id
        )
        let merged = MergeSyncPolicy.merge(
            local: nil,
            remote: remote,
            rules: [],
            preferSuggestedCategory: true
        )
        #expect(merged.categoryID == SystemCategory.income.id)
        #expect(merged.categorySource == .keyword)
    }

    @Test("Locked category ignores matching rule and keeps source")
    func lockedKeepsCategory() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Coffee")]
        )
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -10,
            postedDate: .now,
            description: "Coffee Shop",
            categoryID: SystemCategory.hidden.id,
            userEditedCategory: true,
            categoryLocked: true,
            categorySource: .user
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "Coffee Shop",
            categoryID: SystemCategory.groceries.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [rule])
        #expect(merged.categoryID == SystemCategory.hidden.id)
        #expect(merged.categorySource == .user)
        #expect(merged.userEditedCategory == true)
        #expect(merged.categoryLocked == true)
    }

    @Test("Matching rule overwrites unlocked user category and stamps rule")
    func ruleOverwritesUser() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Coffee")]
        )
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -10,
            postedDate: .now,
            description: "old",
            categoryID: SystemCategory.hidden.id,
            userEditedCategory: true,
            categorySource: .user
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "Coffee Shop",
            categoryID: SystemCategory.groceries.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [rule])
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.categorySource == .rule)
        #expect(merged.userEditedCategory == true)
    }

    @Test("Legacy sticky bool without source backfills to user")
    func legacyNilBoolSticky() {
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -10,
            postedDate: .now,
            description: "MERCHANT",
            categoryID: SystemCategory.shopping.id,
            userEditedCategory: true,
            categorySource: nil
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -11,
            postedDate: .now,
            description: "MERCHANT",
            categoryID: SystemCategory.dining.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [])
        #expect(merged.categoryID == SystemCategory.shopping.id)
        #expect(merged.categorySource == .user)
        #expect(merged.userEditedCategory == true)
    }

    @Test("Legacy processed real category without source backfills keyword")
    func legacyProcessedBackfillKeyword() {
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -10,
            postedDate: .now,
            description: "MERCHANT",
            categoryID: SystemCategory.shopping.id,
            userEditedCategory: false,
            categorySource: nil
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -11,
            postedDate: .now,
            description: "MERCHANT",
            categoryID: SystemCategory.dining.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [])
        #expect(merged.categoryID == SystemCategory.shopping.id)
        #expect(merged.categorySource == .keyword)
        #expect(merged.userEditedCategory == false)
    }

    @Test("Locked legacy sticky backfills user on merge output")
    func lockedLegacyBackfill() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Coffee")]
        )
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -10,
            postedDate: .now,
            description: "Coffee Shop",
            categoryID: SystemCategory.hidden.id,
            userEditedCategory: true,
            categoryLocked: true,
            categorySource: nil
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: .now,
            description: "Coffee Shop",
            categoryID: SystemCategory.groceries.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [rule])
        #expect(merged.categoryID == SystemCategory.hidden.id)
        #expect(merged.categorySource == .user)
        #expect(merged.userEditedCategory == true)
    }

    @Test("effectiveCategorySource backfills legacy sticky and processed")
    func effectiveCategorySourceHelpers() {
        let sticky = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -1,
            postedDate: .now,
            description: "x",
            categoryID: SystemCategory.dining.id,
            userEditedCategory: true,
            categorySource: nil
        )
        #expect(sticky.effectiveCategorySource == .user)
        #expect(sticky.derivedUserEditedCategory == true)

        let processed = Transaction(
            id: TransactionID("t2"),
            accountID: account,
            externalID: "ext2",
            amount: -1,
            postedDate: .now,
            description: "y",
            categoryID: SystemCategory.shopping.id,
            userEditedCategory: false,
            categorySource: nil
        )
        #expect(processed.effectiveCategorySource == .keyword)
        #expect(processed.derivedUserEditedCategory == false)

        let assignment = CategoryAssignment(
            transactionID: TransactionID("t3"),
            categoryID: SystemCategory.dining.id,
            categorySource: .llm
        )
        #expect(assignment.userEditedCategory == false)
        #expect(assignment.categorySource == .llm)
    }
}
