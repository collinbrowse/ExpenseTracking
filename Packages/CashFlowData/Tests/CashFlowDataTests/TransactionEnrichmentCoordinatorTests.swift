import Testing
import Foundation
@testable import CashFlowData
import CashFlowKit

@Suite("TransactionEnrichmentCoordinator")
struct TransactionEnrichmentCoordinatorTests {
    @Test("Skips work when model unavailable")
    func skipsWhenUnavailable() async {
        let txs = MockEnrichmentTransactionRepository(
            needing: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "e",
                    amount: -9,
                    postedDate: .now,
                    description: "STARBUCKS BANGKOK TH",
                    categoryID: SystemCategory.other.id
                ),
            ]
        )
        let coordinator = TransactionEnrichmentCoordinator(
            availability: FixedAvailability(.deviceNotEligible),
            descriptionEnricher: StubDescriptionEnricher(
                result: ParsedTransactionDescription(
                    title: "Starbucks",
                    location: "Bangkok",
                    raw: "STARBUCKS BANGKOK TH"
                )
            ),
            categoryEnricher: StubCategoryEnricher(id: SystemCategory.dining.id),
            transactionRepository: txs,
            ruleRepository: EmptyRuleRepository(),
            workCoordinator: FoundationModelsWorkCoordinator()
        )
        await coordinator.enrichAfterSync()
        #expect(txs.enrichmentUpdates.isEmpty)
        #expect(txs.categoryAssignments.isEmpty)
    }

    @Test("Writes description enrichment and Other→LLM category")
    func enrichesDescriptionAndCategory() async {
        let txs = MockEnrichmentTransactionRepository(
            needing: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "e",
                    amount: -9,
                    postedDate: .now,
                    description: "STARBUCKS BANGKOK TH",
                    categoryID: SystemCategory.other.id
                ),
            ],
            all: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "e",
                    amount: -9,
                    postedDate: .now,
                    description: "STARBUCKS BANGKOK TH",
                    categoryID: SystemCategory.other.id
                ),
            ]
        )
        let coordinator = TransactionEnrichmentCoordinator(
            availability: FixedAvailability(.available),
            descriptionEnricher: StubDescriptionEnricher(
                result: ParsedTransactionDescription(
                    title: "Starbucks",
                    location: "Bangkok",
                    raw: "STARBUCKS BANGKOK TH"
                )
            ),
            categoryEnricher: StubCategoryEnricher(id: SystemCategory.dining.id),
            transactionRepository: txs,
            ruleRepository: EmptyRuleRepository(),
            workCoordinator: FoundationModelsWorkCoordinator()
        )
        await coordinator.enrichAfterSync()
        #expect(txs.enrichmentUpdates.count == 1)
        #expect(txs.enrichmentUpdates[0].title == "Starbucks")
        #expect(txs.enrichmentUpdates[0].location == "Bangkok")
        #expect(txs.categoryAssignments.count == 1)
        #expect(txs.categoryAssignments[0].categoryID == SystemCategory.dining.id)
        #expect(txs.categoryAssignments[0].userEditedCategory == false)
    }
}

private struct FixedAvailability: OnDeviceModelAvailabilityChecking {
    let value: OnDeviceModelAvailability
    init(_ value: OnDeviceModelAvailability) { self.value = value }
    func availability() async -> OnDeviceModelAvailability { value }
}

private struct StubDescriptionEnricher: TransactionDescriptionEnriching {
    let result: ParsedTransactionDescription
    func enrich(rawDescription: String) async -> ParsedTransactionDescription { result }
}

private struct StubCategoryEnricher: TransactionCategoryEnriching {
    let id: CategoryID?
    func suggestCategory(description: String, amount: Decimal) async -> CategoryID? { id }
}

private struct EmptyRuleRepository: CategorizationRuleRepository {
    func fetchAll() async throws -> [CategorizationRule] { [] }
    func upsert(_ rule: CategorizationRule) async throws {}
    func delete(id: CategorizationRuleID) async throws {}
    func reorder(ids: [CategorizationRuleID]) async throws {}
}

private final class MockEnrichmentTransactionRepository: TransactionRepository, @unchecked Sendable {
    var needing: [Transaction]
    var all: [Transaction]
    var enrichmentUpdates: [(id: TransactionID, title: String, location: String?)] = []
    var categoryAssignments: [CategoryAssignment] = []

    init(needing: [Transaction], all: [Transaction]? = nil) {
        self.needing = needing
        self.all = all ?? needing
    }

    func fetchPage(
        filter: TransactionFilter,
        cursor: TransactionCursor?,
        limit: Int
    ) async throws -> TransactionPage {
        TransactionPage(items: [], nextCursor: nil)
    }

    func fetchPosted(in range: CashFlowDateRange, now: Date) async throws -> [Transaction] { [] }
    func earliestPostedDate() async throws -> Date? { nil }
    func updateCategory(
        transactionID: TransactionID,
        categoryID: CategoryID,
        categoryLocked: Bool
    ) async throws {}
    func updateTags(transactionID: TransactionID, tagIDs: [TagID]) async throws {}
    func applyCategoryAssignments(_ assignments: [CategoryAssignment]) async throws {
        categoryAssignments.append(contentsOf: assignments)
    }
    func applyTagAssignments(_ assignments: [TagAssignment]) async throws {}
    func updateEnrichment(
        transactionID: TransactionID,
        title: String,
        location: String?,
        source: TitleSource,
        clearLocation: Bool
    ) async throws {
        enrichmentUpdates.append((transactionID, title, location))
        needing.removeAll { $0.id == transactionID }
    }
    func markEnrichmentSkipped(transactionID: TransactionID) async throws {
        needing.removeAll { $0.id == transactionID }
    }
    func fetchAllForCategorization() async throws -> [Transaction] { all }
    
    func applyTitleLocationAssignments(_ assignments: [TitleLocationAssignment]) async throws {}
    func countNeedingEnrichment() async throws -> Int { needing.count }
    func countDistinctDescriptionsNeedingEnrichment() async throws -> Int { needing.count }

    func fetchNeedingEnrichment(limit: Int) async throws -> [Transaction] {
        Array(needing.prefix(limit))
    }
}
