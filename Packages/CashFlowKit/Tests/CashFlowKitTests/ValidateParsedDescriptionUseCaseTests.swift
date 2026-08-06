import Foundation
import Testing
import CashFlowKit

@Suite("ValidateParsedDescriptionUseCase")
struct ValidateParsedDescriptionUseCaseTests {
    @Test("Accepts title and location tokens present in raw")
    func acceptsValidParse() {
        let parsed = ValidateParsedDescriptionUseCase.execute(
            title: "Kroger",
            location: "Fort Collins CO",
            rawDescription: "KROGER #412 FORT COLLINS CO"
        )
        #expect(parsed?.title == "Kroger")
        #expect(parsed?.location == "Fort Collins CO")
    }

    @Test("Rejects schema type name leak")
    func rejectsGenerableMerchantParse() {
        let parsed = ValidateParsedDescriptionUseCase.execute(
            title: "GenerableMerchantParse",
            location: nil,
            rawDescription: "MOBILE DEPOSIT"
        )
        #expect(parsed == nil)
    }

    @Test("Rejects invented location")
    func rejectsInventedLocation() {
        let parsed = ValidateParsedDescriptionUseCase.execute(
            title: "Starbucks",
            location: "Bangkok",
            rawDescription: "STARBUCKS STORE 12345 SEATTLE WA"
        )
        #expect(parsed == nil)
    }

    @Test("Rejects over-long title")
    func rejectsOverLongTitle() {
        let long = String(repeating: "a", count: ValidateParsedDescriptionUseCase.maxTitleLength + 1)
        let parsed = ValidateParsedDescriptionUseCase.execute(
            title: long,
            location: nil,
            rawDescription: long
        )
        #expect(parsed == nil)
    }

    @Test("Rejects empty title")
    func rejectsEmptyTitle() {
        let parsed = ValidateParsedDescriptionUseCase.execute(
            title: "   ",
            location: nil,
            rawDescription: "STARBUCKS"
        )
        #expect(parsed == nil)
    }
}

@Suite("Transaction display")
struct TransactionDisplayTests {
    @Test("Unenriched displayTitle equals raw description")
    func unenrichedUsesRaw() {
        let tx = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e",
            amount: -5,
            postedDate: .now,
            description: "KROGER #412          FORT COLLINS CO",
            categoryID: SystemCategory.other.id
        )
        #expect(tx.displayTitle == "KROGER #412          FORT COLLINS CO")
        #expect(tx.displayLocation == nil)
    }

    @Test("Enriched display prefers cache")
    func enrichedPrefersCache() {
        let tx = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e",
            amount: -5,
            postedDate: .now,
            description: "KROGER #412 FORT COLLINS CO",
            categoryID: SystemCategory.other.id,
            enrichedTitle: "Kroger",
            enrichedLocation: "Fort Collins CO",
            titleSource: .llm
        )
        #expect(tx.displayTitle == "Kroger")
        #expect(tx.displayLocation == "Fort Collins CO")
    }
}

@Suite("TitleSource precedence")
struct TitleSourcePrecedenceTests {
    @Test("User beats rule and llm")
    func userWins() {
        #expect(TitleSource.canOverwrite(existing: .user, with: .llm) == false)
        #expect(TitleSource.canOverwrite(existing: .user, with: .rule) == false)
        #expect(TitleSource.canOverwrite(existing: .rule, with: .user) == true)
        #expect(TitleSource.canOverwrite(existing: .llm, with: .rule) == true)
        #expect(TitleSource.canOverwrite(existing: nil, with: .llm) == true)
        #expect(TitleSource.canOverwrite(existing: .skipped, with: .llm) == true)
        #expect(TitleSource.canOverwrite(existing: .llm, with: .skipped) == false)
    }
}

@Suite("Rule title matching across enrichment")
struct RuleHaystackStabilityTests {
    @Test("titleContains matches raw and enriched equally")
    func titleContainsStable() {
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.groceries.id,
            priority: 0,
            conditions: [.titleContains("KROGER")],
            appliesCategory: true
        )
        let raw = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e",
            amount: -10,
            postedDate: .now,
            description: "KROGER #412 FORT COLLINS CO",
            categoryID: SystemCategory.other.id
        )
        let enriched = Transaction(
            id: TransactionID("1"),
            accountID: AccountID("a"),
            externalID: "e",
            amount: -10,
            postedDate: .now,
            description: "KROGER #412 FORT COLLINS CO",
            categoryID: SystemCategory.other.id,
            enrichedTitle: "Kroger",
            enrichedLocation: "Fort Collins CO",
            titleSource: .llm
        )
        #expect(CategorizationRuleMatcher.matches(rule, transaction: raw))
        #expect(CategorizationRuleMatcher.matches(rule, transaction: enriched))
    }
}
