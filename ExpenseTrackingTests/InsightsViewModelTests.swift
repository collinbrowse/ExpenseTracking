import Foundation
import Testing
import CashFlowKit
import CashFlowData
@testable import ExpenseTracking

@Suite("InsightsViewModel")
@MainActor
struct InsightsViewModelTests {
    @Test("Reload builds category and tag spending rows")
    func reloadBuildsBreakdown() async throws {
        let trip = CashFlowKit.Tag(id: TagID("trip"), name: "Japan Trip", createdAt: .distantPast)
        let repo = InsightsMockTransactionRepository(
            transactions: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "1",
                    amount: -80,
                    postedDate: .now,
                    description: "Hotel",
                    categoryID: SystemCategory.travelVacation.id,
                    tagIDs: [trip.id]
                ),
                Transaction(
                    id: TransactionID("2"),
                    accountID: AccountID("a"),
                    externalID: "2",
                    amount: -20,
                    postedDate: .now,
                    description: "Food",
                    categoryID: SystemCategory.dining.id,
                    tagIDs: [trip.id]
                ),
                Transaction(
                    id: TransactionID("3"),
                    accountID: AccountID("a"),
                    externalID: "3",
                    amount: 500,
                    postedDate: .now,
                    description: "Pay",
                    categoryID: SystemCategory.income.id
                ),
            ]
        )
        let tags = InsightsMockTagRepository(tags: [trip])
        let vm = InsightsViewModel(
            transactionRepository: repo,
            tagRepository: tags,
            syncServing: InsightsMockSyncServing(),
            calculateSpendingBreakdown: CalculateSpendingBreakdownUseCase()
        )
        await vm.reload()
        #expect(vm.hasExpenseData)
        #expect(vm.categoryRows.count == 2)
        #expect(vm.tagRows.count == 1)
        #expect(vm.tagRows.first?.total == 100)
        #expect(vm.expenseTotalText == CurrencyFormatting.usd(100))
    }

    @Test("Tag focus scopes category breakdown; combining with category ANDs filters")
    func combinedFocusFilters() async throws {
        let trip = CashFlowKit.Tag(id: TagID("trip"), name: "Japan Trip", createdAt: .distantPast)
        let repo = InsightsMockTransactionRepository(
            transactions: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "1",
                    amount: -50,
                    postedDate: .now,
                    description: "Fee",
                    categoryID: SystemCategory.feesCharges.id,
                    tagIDs: [trip.id]
                ),
                Transaction(
                    id: TransactionID("2"),
                    accountID: AccountID("a"),
                    externalID: "2",
                    amount: -20,
                    postedDate: .now,
                    description: "Food",
                    categoryID: SystemCategory.dining.id,
                    tagIDs: [trip.id]
                ),
                Transaction(
                    id: TransactionID("3"),
                    accountID: AccountID("a"),
                    externalID: "3",
                    amount: -15,
                    postedDate: .now,
                    description: "Other fee",
                    categoryID: SystemCategory.feesCharges.id
                ),
            ]
        )
        let vm = InsightsViewModel(
            transactionRepository: repo,
            tagRepository: InsightsMockTagRepository(tags: [trip]),
            syncServing: InsightsMockSyncServing(),
            calculateSpendingBreakdown: CalculateSpendingBreakdownUseCase()
        )
        await vm.reload()
        vm.toggleTagFocus(trip.id)
        #expect(vm.expenseTotalText == CurrencyFormatting.usd(70))
        #expect(vm.categoryRows.count == 2)

        vm.toggleCategoryFocus(SystemCategory.feesCharges.id)
        #expect(vm.expenseTotalText == CurrencyFormatting.usd(50))
        #expect(vm.categoryRows.map(\.id) == [SystemCategory.feesCharges.id.rawValue])
        #expect(vm.tagRows.map(\.id) == [trip.id.rawValue])
    }
}

private struct InsightsMockTransactionRepository: TransactionRepository {
    let transactions: [Transaction]

    func fetchPage(
        filter: TransactionFilter,
        cursor: TransactionCursor?,
        limit: Int
    ) async throws -> TransactionPage {
        TransactionPage(items: Array(transactions.prefix(limit)), nextCursor: nil)
    }

    func fetchPosted(in range: CashFlowDateRange, now: Date) async throws -> [Transaction] {
        transactions
    }

    func earliestPostedDate() async throws -> Date? {
        transactions.map(\.postedDate).min()
    }

    func updateCategory(
        transactionID: TransactionID,
        categoryID: CategoryID,
        categoryLocked: Bool
    ) async throws {}
    func updateTags(transactionID: TransactionID, tagIDs: [TagID]) async throws {}
    func applyCategoryAssignments(_ assignments: [CategoryAssignment]) async throws {}
    func applyTagAssignments(_ assignments: [TagAssignment]) async throws {}
    func updateEnrichment(
        transactionID: TransactionID,
        title: String,
        location: String?,
        source: TitleSource,
        clearLocation: Bool
    ) async throws {}
    func markEnrichmentSkipped(transactionID: TransactionID) async throws {}
    func fetchAllForCategorization() async throws -> [Transaction] { transactions }
    
    func applyTitleLocationAssignments(_ assignments: [TitleLocationAssignment]) async throws {}
    func countNeedingEnrichment() async throws -> Int { 0 }
    func countDistinctDescriptionsNeedingEnrichment() async throws -> Int { 0 }

    func fetchNeedingEnrichment(limit: Int) async throws -> [Transaction] {
        Array(transactions.filter { $0.enrichedTitle == nil }.prefix(limit))
    }
}

private final class InsightsMockTagRepository: TagRepository, @unchecked Sendable {
    private var tags: [CashFlowKit.Tag]

    init(tags: [CashFlowKit.Tag]) {
        self.tags = tags
    }

    func fetchAll() async throws -> [CashFlowKit.Tag] { tags }

    func create(name: String) async throws -> CashFlowKit.Tag {
        let tag = CashFlowKit.Tag(id: TagID(UUID().uuidString), name: name, createdAt: .now)
        tags.append(tag)
        return tag
    }

    func rename(id: TagID, name: String) async throws {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index] = CashFlowKit.Tag(id: id, name: name, createdAt: tags[index].createdAt)
    }

    func delete(id: TagID) async throws {
        tags.removeAll { $0.id == id }
    }
}

private struct InsightsMockSyncServing: SyncServing {
    func syncNow() async throws -> LinkedConnection {
        LinkedConnection(isLinked: true, providerName: "Mock")
    }

    func connectionStatus() async -> LinkedConnection {
        LinkedConnection(isLinked: true, providerName: "Mock")
    }
}
