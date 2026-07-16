import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("Demo net cash flow")
struct DemoNetCashFlowTests {
    @Test("Home monthly net matches summed demo transactions in range")
    func monthlyNetMatchesTransactions() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let demo = DemoBankLinkingService(seedSize: .standard)
        try await demo.link(withSetupToken: "demo")
        let payload = try await demo.fetchAccounts(startDate: nil, endDate: nil)
        let context = ModelContext(container)
        try SyncMergeEngine.merge(payload: payload, into: context)

        let repo = SwiftDataTransactionRepository(modelContainer: container)
        let range = CashFlowDateRange.month(.now)
        let transactions = try await repo.fetchPosted(in: range, now: .now)
        #expect(!transactions.isEmpty)

        let result = CalculateNetCashFlowUseCase().execute(
            transactions: transactions,
            range: range
        )

        var expectedIncome: Decimal = 0
        var expectedExpense: Decimal = 0
        for tx in transactions {
            switch CashFlowContribution.forTransaction(tx) {
            case .income: expectedIncome += abs(tx.amount)
            case .expense: expectedExpense += abs(tx.amount)
            case .none: break
            }
        }
        #expect(result.incomeTotal == expectedIncome)
        #expect(result.expenseTotal == expectedExpense)
        #expect(result.net == expectedIncome - expectedExpense)
        #expect(result.net != 0)
    }
}
