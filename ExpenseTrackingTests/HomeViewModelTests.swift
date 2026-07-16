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
        transactions
    }

    func updateCategory(transactionID: TransactionID, categoryID: CategoryID) async throws {}
    func updateDescription(transactionID: TransactionID, description: String) async throws {}
}

private struct MockSyncServing: SyncServing {
    func syncNow() async throws -> LinkedConnection {
        LinkedConnection(isLinked: true, providerName: "Mock")
    }

    func connectionStatus() async -> LinkedConnection {
        LinkedConnection(isLinked: true, providerName: "Mock")
    }
}
