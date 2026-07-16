import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("SyncMergeEngine")
struct SyncMergeEngineTests {
    @Test("Idempotent upsert by sync key")
    func idempotentUpsert() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let payload = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Checking",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: 100,
                balanceDate: .now,
                transactions: [
                    RemoteTransactionSnapshot(
                        externalID: "t1",
                        amount: -20,
                        postedDate: Date(timeIntervalSince1970: 1_700_000_000),
                        description: "Coffee",
                        suggestedCategoryID: SystemCategory.dining.id
                    ),
                ]
            ),
        ])
        try SyncMergeEngine.merge(payload: payload, into: context)
        try SyncMergeEngine.merge(payload: payload, into: context)

        let txs = try context.fetch(FetchDescriptor<TransactionEntity>())
        #expect(txs.count == 1)
        #expect(txs.first?.amount == -20)
    }

    @Test("User-edited category preserved on re-sync")
    func preserveCategory() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let repo = SwiftDataTransactionRepository(modelContainer: container)
        let context = ModelContext(container)

        let payload = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Checking",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: 100,
                balanceDate: .now,
                transactions: [
                    RemoteTransactionSnapshot(
                        externalID: "t1",
                        amount: -20,
                        postedDate: Date(timeIntervalSince1970: 1_700_000_000),
                        description: "Coffee",
                        suggestedCategoryID: SystemCategory.dining.id
                    ),
                ]
            ),
        ])
        try SyncMergeEngine.merge(payload: payload, into: context)

        let page = try await repo.fetchPage(filter: .all, cursor: nil, limit: 50)
        let id = try #require(page.items.first?.id)
        try await repo.updateCategory(transactionID: id, categoryID: SystemCategory.hidden.id)

        let updatedPayload = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Checking",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: 100,
                balanceDate: .now,
                transactions: [
                    RemoteTransactionSnapshot(
                        externalID: "t1",
                        amount: -25,
                        postedDate: Date(timeIntervalSince1970: 1_700_000_100),
                        description: "Coffee Shop",
                        suggestedCategoryID: SystemCategory.groceries.id
                    ),
                ]
            ),
        ])
        try SyncMergeEngine.merge(payload: updatedPayload, into: context)
        let page2 = try await repo.fetchPage(filter: .all, cursor: nil, limit: 50)
        let tx = try #require(page2.items.first)
        #expect(tx.categoryID == SystemCategory.hidden.id)
        #expect(tx.amount == -25)
        #expect(tx.description == "Coffee Shop")
        #expect(tx.userEditedCategory == true)
    }

    @Test("Keyset pagination returns stable pages")
    func keysetPagination() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let demo = DemoBankLinkingService(seedSize: .standard)
        try await demo.link(withSetupToken: "demo")
        let payload = try await demo.fetchAccounts(startDate: nil, endDate: nil)
        let context = ModelContext(container)
        try SyncMergeEngine.merge(payload: payload, into: context)

        let repo = SwiftDataTransactionRepository(modelContainer: container)
        let page1 = try await repo.fetchPage(filter: .all, cursor: nil, limit: 50)
        #expect(page1.items.count == 50)
        #expect(page1.nextCursor != nil)

        let page2 = try await repo.fetchPage(
            filter: .all,
            cursor: page1.nextCursor,
            limit: 50
        )
        #expect(!page2.items.isEmpty)
        let ids1 = Set(page1.items.map(\.id))
        let ids2 = Set(page2.items.map(\.id))
        #expect(ids1.isDisjoint(with: ids2))
    }
}
