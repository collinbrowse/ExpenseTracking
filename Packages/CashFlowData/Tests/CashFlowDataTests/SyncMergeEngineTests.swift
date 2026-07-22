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
        try await repo.updateCategory(
            transactionID: id,
            categoryID: SystemCategory.hidden.id,
            categoryLocked: false
        )

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
        #expect(tx.description == "Coffee")
        #expect(tx.userEditedCategory == true)
    }

    @Test("User-edited account name preserved on re-sync")
    func preserveAccountName() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let repo = SwiftDataAccountRepository(modelContainer: container)
        let context = ModelContext(container)

        let payload = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Checking",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: 100,
                balanceDate: .now,
                transactions: []
            ),
        ])
        try SyncMergeEngine.merge(payload: payload, into: context)

        let accounts = try await repo.fetchAll()
        let id = try #require(accounts.first?.id)
        try await repo.updateName(accountID: id, name: "Everyday Spending")

        let updatedPayload = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "CHK ****1234",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: 250,
                balanceDate: .now,
                transactions: []
            ),
        ])
        try SyncMergeEngine.merge(payload: updatedPayload, into: context)

        let after = try await repo.fetchAll()
        let account = try #require(after.first)
        #expect(account.name == "Everyday Spending")
        #expect(account.balance == 250)

        let entities = try ModelContext(container).fetch(FetchDescriptor<AccountEntity>())
        #expect(entities.first?.userEditedName == true)
    }

    @Test("Account syncIssue persists and clears on clean sync")
    func accountSyncIssueRoundTrip() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let broken = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Checking",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: 10,
                balanceDate: .now,
                transactions: [],
                connectionExternalID: "c1",
                syncIssue: "Authentication failed for Bank"
            ),
        ])
        try SyncMergeEngine.merge(payload: broken, into: context)

        let repo = SwiftDataAccountRepository(modelContainer: container)
        let afterBroken = try #require(try await repo.fetchAll().first)
        #expect(afterBroken.syncIssue == "Authentication failed for Bank")
        #expect(afterBroken.hasSyncIssue)

        let healthy = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Checking",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: 12,
                balanceDate: .now,
                transactions: [],
                connectionExternalID: "c1",
                syncIssue: nil
            ),
        ])
        try SyncMergeEngine.merge(payload: healthy, into: context)
        let afterHealthy = try #require(try await repo.fetchAll().first)
        #expect(afterHealthy.syncIssue == nil)
        #expect(!afterHealthy.hasSyncIssue)
        #expect(afterHealthy.balance == 12)
    }

    @Test("Pending transactions persist and flip to posted on same sync key")
    func pendingPersistsThenPosts() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let pendingDate = Date(timeIntervalSince1970: 1_700_000_000)

        let pendingPayload = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Card",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: -50,
                balanceDate: .now,
                transactions: [
                    RemoteTransactionSnapshot(
                        externalID: "t-pending",
                        amount: -42,
                        postedDate: pendingDate,
                        description: "RESTAURANT",
                        isPending: true,
                        suggestedCategoryID: SystemCategory.dining.id
                    ),
                ]
            ),
        ])
        try SyncMergeEngine.merge(payload: pendingPayload, into: context)

        let repo = SwiftDataTransactionRepository(modelContainer: container)
        let pendingPage = try await repo.fetchPage(filter: .all, cursor: nil, limit: 50)
        let pendingTx = try #require(pendingPage.items.first)
        #expect(pendingTx.isPending)
        #expect(pendingTx.amount == -42)

        let postedPayload = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Card",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: -50,
                balanceDate: .now,
                transactions: [
                    RemoteTransactionSnapshot(
                        externalID: "t-pending",
                        amount: -42,
                        postedDate: pendingDate,
                        description: "RESTAURANT",
                        isPending: false,
                        suggestedCategoryID: SystemCategory.dining.id
                    ),
                ]
            ),
        ])
        try SyncMergeEngine.merge(payload: postedPayload, into: context)

        let postedPage = try await repo.fetchPage(filter: .all, cursor: nil, limit: 50)
        #expect(postedPage.items.count == 1)
        let postedTx = try #require(postedPage.items.first)
        #expect(!postedTx.isPending)
        #expect(postedTx.id == pendingTx.id)
    }

    @Test("Stale pending rows are removed when absent from pending-capable payload")
    func stalePendingRemoved() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)

        let withPending = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Card",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: -10,
                balanceDate: .now,
                transactions: [
                    RemoteTransactionSnapshot(
                        externalID: "gone",
                        amount: -10,
                        postedDate: .now,
                        description: "TEMP",
                        isPending: true
                    ),
                ]
            ),
        ])
        try SyncMergeEngine.merge(payload: withPending, into: context)
        #expect(try context.fetch(FetchDescriptor<TransactionEntity>()).count == 1)

        let cleared = RemoteSyncPayload(accounts: [
            RemoteAccountSnapshot(
                externalID: "a1",
                name: "Card",
                institutionName: "Bank",
                currencyCode: "USD",
                balance: -10,
                balanceDate: .now,
                transactions: []
            ),
        ])
        try SyncMergeEngine.merge(payload: cleared, into: context)
        #expect(try context.fetch(FetchDescriptor<TransactionEntity>()).isEmpty)
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
