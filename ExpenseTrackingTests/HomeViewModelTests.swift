import Foundation
import Testing
import CashFlowKit
import CashFlowData
@testable import ExpenseTracking

@Suite("HomeViewModel")
@MainActor
struct HomeViewModelTests {
    @Test("Reload computes net from repository transactions")
    func reloadComputesNet() async throws {
        let repo = MockTransactionRepository(
            transactions: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "1",
                    amount: 1000,
                    postedDate: .now,
                    description: "Pay",
                    categoryID: SystemCategory.income.id
                ),
                Transaction(
                    id: TransactionID("2"),
                    accountID: AccountID("a"),
                    externalID: "2",
                    amount: -100,
                    postedDate: .now,
                    description: "Food",
                    categoryID: SystemCategory.dining.id
                ),
            ]
        )
        let sync = MockSyncServing()
        let vm = HomeViewModel(
            transactionRepository: repo,
            syncServing: sync,
            calculateNetCashFlow: CalculateNetCashFlowUseCase(),
            connectivity: ConnectivityMonitor()
        )
        await vm.reload()
        #expect(vm.result.net == 900)
        #expect(vm.hasData)
        #expect(!vm.availableRangeOptions.contains(.lastYear))
    }

    @Test("Year appears only when local history reaches back a full year")
    func yearRequiresFullYearHistory() async {
        let now = Date()
        let recentRepo = MockTransactionRepository(
            transactions: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "1",
                    amount: -10,
                    postedDate: Calendar.current.date(byAdding: .day, value: -40, to: now) ?? now,
                    description: "Recent",
                    categoryID: SystemCategory.dining.id
                ),
            ]
        )
        let recentVM = HomeViewModel(
            transactionRepository: recentRepo,
            syncServing: MockSyncServing(),
            calculateNetCashFlow: CalculateNetCashFlowUseCase(),
            connectivity: ConnectivityMonitor()
        )
        await recentVM.reload()
        #expect(!recentVM.availableRangeOptions.contains(.lastYear))

        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        let deepRepo = MockTransactionRepository(
            transactions: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "1",
                    amount: -10,
                    postedDate: yearAgo,
                    description: "Old",
                    categoryID: SystemCategory.dining.id
                ),
            ]
        )
        let deepVM = HomeViewModel(
            transactionRepository: deepRepo,
            syncServing: MockSyncServing(),
            calculateNetCashFlow: CalculateNetCashFlowUseCase(),
            connectivity: ConnectivityMonitor()
        )
        await deepVM.reload()
        #expect(deepVM.availableRangeOptions.contains(.lastYear))
    }

    @Test("Empty month still shows populated UI when store has older history")
    func emptyMonthKeepsPopulatedState() async {
        let now = Date()
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let repo = MockTransactionRepository(
            transactions: [
                Transaction(
                    id: TransactionID("1"),
                    accountID: AccountID("a"),
                    externalID: "1",
                    amount: -40,
                    postedDate: lastMonth,
                    description: "Old spend",
                    categoryID: SystemCategory.dining.id
                ),
            ]
        )
        let vm = HomeViewModel(
            transactionRepository: repo,
            syncServing: MockSyncServing(),
            calculateNetCashFlow: CalculateNetCashFlowUseCase(),
            connectivity: ConnectivityMonitor()
        )
        vm.selectedOption = .last30Days
        await vm.reload()
        #expect(vm.hasStoreHistory)
        #expect(vm.displayState == .populated)

        vm.selectOption(.month)
        // Allow scheduled reload to finish.
        await vm.reload(preferLoadingIndicator: false)
        #expect(vm.selectedOption == .month)
        #expect(vm.hasStoreHistory)
        #expect(!vm.hasData)
        #expect(vm.displayState == .populated)
        #expect(vm.result.net == 0)
    }
}

private struct MockTransactionRepository: TransactionRepository {
    let transactions: [Transaction]

    func fetchPage(
        filter: TransactionFilter,
        cursor: TransactionCursor?,
        limit: Int
    ) async throws -> TransactionPage {
        TransactionPage(items: Array(transactions.prefix(limit)), nextCursor: nil)
    }

    func fetchPosted(in range: CashFlowDateRange, now: Date) async throws -> [Transaction] {
        let interval = range.interval(now: now)
        return transactions.filter { tx in
            !tx.isPending
                && tx.postedDate >= interval.start
                && tx.postedDate <= interval.end
        }
    }

    func earliestPostedDate() async throws -> Date? {
        transactions.filter { !$0.isPending }.map(\.postedDate).min()
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
    func fetchNeedingCategorySuggestion(limit: Int) async throws -> [Transaction] { [] }
    func countNeedingCategorySuggestion() async throws -> Int { 0 }
    
    func applyTitleLocationAssignments(_ assignments: [TitleLocationAssignment]) async throws {}
    func countNeedingEnrichment() async throws -> Int { 0 }
    func countDistinctDescriptionsNeedingEnrichment() async throws -> Int { 0 }

    func fetchNeedingEnrichment(limit: Int) async throws -> [Transaction] {
        Array(transactions.filter { $0.enrichedTitle == nil }.prefix(limit))
    }
}

private struct MockSyncServing: SyncServing {
    func syncNow() async throws -> LinkedConnection {
        LinkedConnection(isLinked: true, providerName: "Mock")
    }

    func connectionStatus() async -> LinkedConnection {
        LinkedConnection(isLinked: true, providerName: "Mock")
    }
}
