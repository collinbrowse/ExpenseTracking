import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("Transaction repository search")
struct TransactionRepositorySearchTests {
    @Test("Search finds rows beyond the first keyset page")
    func searchOutsideFirstPage() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let account = AccountEntity(
            id: "acct",
            externalID: "ext-a",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 100,
            balanceDate: .now
        )
        context.insert(account)

        // Newest first in keyset — insert 60 rows so the unique merchant is past page size 50.
        for index in 0..<60 {
            let day = Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 86_400)
            let description = index == 55 ? "UNIQUE_MERCHANT_ZZZ" : "Coffee \(index)"
            context.insert(
                TransactionEntity(
                    id: "tx-\(index)",
                    externalID: "u-\(index)",
                    accountID: account.id,
                    amount: Decimal(-index - 1),
                    postedDate: day,
                    transactionDescription: description,
                    categoryID: SystemCategory.dining.id.rawValue,
                    currencyCode: "USD",
                    userEditedCategory: false,
                    isPending: false,
                    syncKey: "ext-a|u-\(index)",
                    account: account
                )
            )
        }
        try context.save()

        let repo = SwiftDataTransactionRepository(modelContainer: container)
        let unfiltered = try await repo.fetchPage(filter: .all, cursor: nil, limit: 50)
        #expect(unfiltered.items.count == 50)
        #expect(!unfiltered.items.contains(where: { $0.description.contains("UNIQUE_MERCHANT") }))

        let filtered = try await repo.fetchPage(
            filter: TransactionFilter(searchQuery: "UNIQUE_MERCHANT"),
            cursor: nil,
            limit: 50
        )
        #expect(filtered.items.count == 1)
        #expect(filtered.items[0].description == "UNIQUE_MERCHANT_ZZZ")
    }
}
