import Foundation
import Testing
@testable import CashFlowKit

@Suite("CategorizationRuleMatcher")
struct CategorizationRuleMatcherTests {
    private let account = AccountID("acct-1")

    @Test("AND conditions require all clauses")
    func andConditions() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [
                .titleContains("Starbucks"),
                .amountMax(-1),
            ]
        )
        #expect(
            CategorizationRuleMatcher.matches(
                rule,
                description: "STARBUCKS STORE 12345",
                amount: -5.50,
                accountID: account
            )
        )
        #expect(
            !CategorizationRuleMatcher.matches(
                rule,
                description: "STARBUCKS STORE 12345",
                amount: 5.50,
                accountID: account
            )
        )
    }

    @Test("Title equals uses parsed title and normalize")
    func titleEquals() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.shopping.id,
            priority: 0,
            conditions: [.titleEquals("Amazon")]
        )
        #expect(
            CategorizationRuleMatcher.matches(
                rule,
                description: "AMAZON",
                amount: -20,
                accountID: account
            )
        )
        #expect(
            !CategorizationRuleMatcher.matches(
                rule,
                description: "AMAZON MARKETPLACE",
                amount: -20,
                accountID: account
            )
        )
    }

    @Test("Description contains matches full string")
    func descriptionContains() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.other.id,
            priority: 0,
            conditions: [.descriptionContains("Seattle")]
        )
        #expect(
            CategorizationRuleMatcher.matches(
                rule,
                description: "Coffee  Seattle WA",
                amount: -4,
                accountID: account
            )
        )
    }

    @Test("Title contains matches words even when other words sit between them")
    func titleContainsWordsNonAdjacent() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.income.id,
            priority: 0,
            conditions: [.titleContains("Income Payment")]
        )
        #expect(
            CategorizationRuleMatcher.matches(
                rule,
                description: "Income  Benefits Payment, March 2026",
                amount: 100,
                accountID: account
            )
        )
    }

    @Test("Title contains requires whole words, not substrings inside a word")
    func titleContainsWholeWordsOnly() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.other.id,
            priority: 0,
            conditions: [.titleContains("fee")]
        )
        #expect(
            !CategorizationRuleMatcher.matches(
                rule,
                description: "Coffee Shop",
                amount: -4,
                accountID: account
            )
        )
        #expect(
            CategorizationRuleMatcher.matches(
                rule,
                description: "Bank Fee",
                amount: -4,
                accountID: account
            )
        )
    }

    @Test("Account and amount bounds")
    func accountAndAmount() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.bills.id,
            priority: 0,
            conditions: [
                .accountID(account),
                .amountMin(-100),
                .amountMax(-10),
            ]
        )
        #expect(
            CategorizationRuleMatcher.matches(
                rule,
                description: "Utility",
                amount: -50,
                accountID: account
            )
        )
        #expect(
            !CategorizationRuleMatcher.matches(
                rule,
                description: "Utility",
                amount: -50,
                accountID: AccountID("other")
            )
        )
    }

    @Test("First matching rule by priority wins")
    func priorityOrder() {
        let low = CategorizationRule(
            id: CategorizationRuleID("a"),
            categoryID: SystemCategory.dining.id,
            priority: 1,
            conditions: [.titleContains("Coffee")]
        )
        let high = CategorizationRule(
            id: CategorizationRuleID("b"),
            categoryID: SystemCategory.shopping.id,
            priority: 0,
            conditions: [.titleContains("Coffee")]
        )
        let match = CategorizationRuleMatcher.firstMatchingRule(
            [low, high],
            description: "Coffee Place",
            amount: -3,
            accountID: account
        )
        #expect(match?.id == high.id)
    }

    @Test("Disabled rules are skipped")
    func disabledSkipped() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            isEnabled: false,
            conditions: [.titleContains("Coffee")]
        )
        #expect(
            CategorizationRuleMatcher.firstMatchingRule(
                [rule],
                description: "Coffee",
                amount: -3,
                accountID: account
            ) == nil
        )
    }
}

@Suite("ResolveTransactionCategoryUseCase")
struct ResolveTransactionCategoryUseCaseTests {
    private let account = AccountID("a1")

    @Test("Locked keeps current category")
    func lockedKeepsCurrent() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Coffee")]
        )
        let resolved = ResolveTransactionCategoryUseCase.execute(
            description: "Coffee",
            amount: -3,
            accountID: account,
            rules: [rule],
            categoryLocked: true,
            currentCategoryID: SystemCategory.hidden.id
        )
        #expect(resolved.categoryID == SystemCategory.hidden.id)
        #expect(resolved.matchedUserRule == false)
        #expect(resolved.renameTitle == nil)
    }

    @Test("Locked still returns rename from matching rename rule")
    func lockedStillRenames() {
        let rename = CategorizationRule(
            id: CategorizationRuleID("ren"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Coffee")],
            renameTitle: "Coffee Shop",
            appliesCategory: false
        )
        let categorize = CategorizationRule(
            id: CategorizationRuleID("cat"),
            categoryID: SystemCategory.dining.id,
            priority: 1,
            conditions: [.titleContains("Coffee")],
            appliesCategory: true
        )
        let resolved = ResolveTransactionCategoryUseCase.execute(
            description: "Coffee Place",
            amount: -3,
            accountID: account,
            rules: [rename, categorize],
            categoryLocked: true,
            currentCategoryID: SystemCategory.shopping.id
        )
        #expect(resolved.categoryID == SystemCategory.shopping.id)
        #expect(resolved.renameTitle == "Coffee Shop")
        #expect(resolved.matchedUserRule == true)
    }

    @Test("User rule beats fallback")
    func ruleBeatsFallback() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.businessServices.id,
            priority: 0,
            conditions: [.titleContains("Cursor")]
        )
        let resolved = ResolveTransactionCategoryUseCase.execute(
            description: "Cursor AI",
            amount: -20,
            accountID: account,
            rules: [rule],
            categoryLocked: false,
            currentCategoryID: SystemCategory.other.id,
            fallbackCategoryID: SystemCategory.shopping.id
        )
        #expect(resolved.categoryID == SystemCategory.businessServices.id)
        #expect(resolved.matchedUserRule == true)
    }

    @Test("No rule uses fallback then built-in")
    func fallbackThenBuiltin() {
        let withFallback = ResolveTransactionCategoryUseCase.execute(
            description: "Mystery Merchant XYZ",
            amount: -10,
            accountID: account,
            rules: [],
            categoryLocked: false,
            currentCategoryID: SystemCategory.other.id,
            fallbackCategoryID: SystemCategory.travelVacation.id
        )
        #expect(withFallback.categoryID == SystemCategory.travelVacation.id)
        #expect(withFallback.matchedUserRule == false)

        let builtin = ResolveTransactionCategoryUseCase.execute(
            description: "Starbucks",
            amount: -5,
            accountID: account,
            rules: [],
            categoryLocked: false,
            currentCategoryID: SystemCategory.other.id,
            fallbackCategoryID: nil
        )
        #expect(builtin.categoryID == SystemCategory.dining.id)
    }
}

@Suite("MergeSyncPolicy with rules")
struct MergeSyncPolicyRulesTests {
    private let account = AccountID("a")

    @Test("Locked category survives remote and matching rules")
    func lockedSurvives() {
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
            amount: 10,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "old",
            categoryID: SystemCategory.hidden.id,
            userEditedCategory: true,
            categoryLocked: true
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 20,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "Coffee Shop",
            categoryID: SystemCategory.groceries.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [rule])
        #expect(merged.categoryID == SystemCategory.hidden.id)
        #expect(merged.categoryLocked == true)
        #expect(merged.amount == 20)
        #expect(merged.description == "Coffee Shop")
    }

    @Test("Locked still applies rename rule on sync")
    func lockedStillAppliesRename() {
        let rename = CategorizationRule(
            id: CategorizationRuleID("ren"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("STARBUCKS")],
            renameTitle: "Starbucks",
            renameLocation: "Denver CO",
            appliesCategory: false
        )
        let categorize = CategorizationRule(
            id: CategorizationRuleID("cat"),
            categoryID: SystemCategory.dining.id,
            priority: 1,
            conditions: [.titleContains("STARBUCKS")],
            appliesCategory: true
        )
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -5,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "STARBUCKS #99  Denver CO",
            categoryID: SystemCategory.shopping.id,
            userEditedCategory: true,
            categoryLocked: true
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -5,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "STARBUCKS #99  Denver CO",
            categoryID: SystemCategory.other.id
        )
        let merged = MergeSyncPolicy.merge(
            local: local,
            remote: remote,
            rules: [rename, categorize]
        )
        #expect(merged.categoryID == SystemCategory.shopping.id)
        #expect(merged.categoryLocked == true)
        #expect(merged.description == "STARBUCKS #99  Denver CO")
        #expect(merged.enrichedTitle == "Starbucks")
        #expect(merged.enrichedLocation == "Denver CO")
        #expect(merged.titleSource == .rule)
    }

    @Test("Categorize-only match keeps prior local rename enrichment")
    func categorizeOnlyKeepsPriorRename() {
        let categorize = CategorizationRule(
            id: CategorizationRuleID("cat"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("STARBUCKS")],
            appliesCategory: true
        )
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -5,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "STARBUCKS #99  Denver CO",
            categoryID: SystemCategory.shopping.id,
            userEditedCategory: true,
            enrichedTitle: "Starbucks",
            enrichedLocation: "Denver CO",
            titleSource: .rule
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -5,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "STARBUCKS #99  Denver CO",
            categoryID: SystemCategory.other.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [categorize])
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.description == "STARBUCKS #99  Denver CO")
        #expect(merged.enrichedTitle == "Starbucks")
        #expect(merged.enrichedLocation == "Denver CO")
    }

    @Test("Matching rule overwrites unlocked user-edited category")
    func ruleOverwritesUserEdit() {
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
            amount: 10,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "old",
            categoryID: SystemCategory.hidden.id,
            userEditedCategory: true,
            categoryLocked: false
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 20,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "Coffee Shop",
            categoryID: SystemCategory.groceries.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [rule])
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.userEditedCategory == true)
        #expect(merged.categorySource == .rule)
    }

    @Test("Without rule match, user-edited category still wins")
    func userEditWithoutRule() {
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 10,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "old",
            categoryID: SystemCategory.dining.id,
            userEditedCategory: true
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 20,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "new",
            categoryID: SystemCategory.groceries.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [])
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.userEditedCategory == true)
        #expect(merged.description == "new")
    }

    @Test("New remote applies matching rule")
    func newRemoteAppliesRule() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.shopping.id,
            priority: 0,
            conditions: [.titleContains("Amazon")]
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -40,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "AMAZON MARKETPLACE",
            categoryID: SystemCategory.other.id
        )
        let merged = MergeSyncPolicy.merge(local: nil, remote: remote, rules: [rule])
        #expect(merged.categoryID == SystemCategory.shopping.id)
        #expect(merged.userEditedCategory == true)
    }

    @Test("Pending remote skips matching rule until posted")
    func pendingRemoteSkipsRule() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.shopping.id,
            priority: 0,
            conditions: [.titleContains("Amazon")],
            renameTitle: "Amazon",
            tagIDs: [TagID("trip")]
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -40,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "AMAZON MARKETPLACE",
            categoryID: SystemCategory.other.id,
            isPending: true
        )
        let merged = MergeSyncPolicy.merge(local: nil, remote: remote, rules: [rule])
        #expect(merged.isPending)
        #expect(merged.categoryID == SystemCategory.undefined.id)
        #expect(merged.userEditedCategory == false)
        #expect(merged.description == "AMAZON MARKETPLACE")
        #expect(merged.tagIDs.isEmpty)
    }

    @Test("Pending-to-posted merge applies matching rule")
    func pendingToPostedAppliesRule() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.shopping.id,
            priority: 0,
            conditions: [.titleContains("Amazon")],
            renameTitle: "Amazon"
        )
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -40,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "AMAZON MARKETPLACE",
            categoryID: SystemCategory.other.id,
            isPending: true
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -40,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "AMAZON MARKETPLACE",
            categoryID: SystemCategory.other.id,
            isPending: false
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [rule])
        #expect(!merged.isPending)
        #expect(merged.categoryID == SystemCategory.shopping.id)
        #expect(merged.userEditedCategory == true)
        #expect(merged.description == "AMAZON MARKETPLACE")
        #expect(merged.enrichedTitle == "Amazon")
        #expect(merged.titleSource == .rule)
    }

    @Test("Still-pending update skips matching rule")
    func stillPendingSkipsRule() {
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
            postedDate: Date(timeIntervalSince1970: 100),
            description: "Coffee Shop",
            categoryID: SystemCategory.other.id,
            isPending: true
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -12,
            postedDate: Date(timeIntervalSince1970: 150),
            description: "Coffee Shop",
            categoryID: SystemCategory.groceries.id,
            isPending: true
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [rule])
        #expect(merged.isPending)
        #expect(merged.amount == -12)
        #expect(merged.categoryID == SystemCategory.undefined.id)
        #expect(merged.userEditedCategory == false)
    }

    @Test("Matching rename rule writes enrichment without mutating bank description")
    func renameOnMatch() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Starbucks")],
            renameTitle: "Starbucks",
            renameLocation: "Seattle WA"
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -5,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "STARBUCKS STORE 12345  Seattle WA",
            categoryID: SystemCategory.other.id
        )
        let merged = MergeSyncPolicy.merge(local: nil, remote: remote, rules: [rule])
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.description == "STARBUCKS STORE 12345  Seattle WA")
        #expect(merged.enrichedTitle == "Starbucks")
        #expect(merged.enrichedLocation == "Seattle WA")
        #expect(merged.titleSource == .rule)
    }

    @Test("Sticky user-edited category keeps enrichment when bank description is unchanged")
    func stickyCategoryKeepsLocalDescription() {
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -5,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "STARBUCKS STORE 12345  Seattle WA",
            categoryID: SystemCategory.dining.id,
            userEditedCategory: true,
            enrichedTitle: "Starbucks",
            titleSource: .user
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: -5,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "STARBUCKS STORE 12345  Seattle WA",
            categoryID: SystemCategory.other.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote, rules: [])
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.description == "STARBUCKS STORE 12345  Seattle WA")
        #expect(merged.enrichedTitle == "Starbucks")
        #expect(merged.titleSource == .user)
        #expect(merged.userEditedCategory == true)
    }

    @Test("Rename-only rule keeps existing category")
    func renameOnlyKeepsCategory() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Starbucks")],
            renameTitle: "Starbucks",
            appliesCategory: false
        )
        let resolved = ResolveTransactionCategoryUseCase.execute(
            description: "STARBUCKS STORE",
            amount: -5,
            accountID: account,
            rules: [rule],
            categoryLocked: false,
            currentCategoryID: SystemCategory.shopping.id
        )
        #expect(resolved.categoryID == SystemCategory.shopping.id)
        #expect(resolved.matchedUserRule == true)
        #expect(resolved.renameTitle == "Starbucks")
    }

    @Test("Categorize and rename rules both apply when both match")
    func categorizeAndRenameIndependently() {
        let categorize = CategorizationRule(
            id: CategorizationRuleID("cat"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Starbucks")],
            appliesCategory: true
        )
        let rename = CategorizationRule(
            id: CategorizationRuleID("ren"),
            categoryID: SystemCategory.other.id,
            priority: 1,
            conditions: [.titleContains("Starbucks")],
            renameTitle: "Starbucks",
            appliesCategory: false
        )
        let resolved = ResolveTransactionCategoryUseCase.execute(
            description: "STARBUCKS STORE 99",
            amount: -5,
            accountID: account,
            rules: [categorize, rename],
            categoryLocked: false,
            currentCategoryID: SystemCategory.shopping.id
        )
        #expect(resolved.categoryID == SystemCategory.dining.id)
        #expect(resolved.renameTitle == "Starbucks")
        #expect(resolved.matchedUserRule == true)
    }

    @Test("Already-renamed title still matches its rename rule")
    func alreadyRenamedStillMatches() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("STARBUCKS STORE")],
            renameTitle: "Starbucks",
            appliesCategory: false
        )
        #expect(
            CategorizationRuleMatcher.matches(
                rule,
                description: "STARBUCKS STORE 12345  Seattle WA",
                amount: -5,
                accountID: account,
                enrichedTitle: "Starbucks",
                enrichedLocation: "Seattle WA",
                titleSource: .rule
            )
        )
    }
}
