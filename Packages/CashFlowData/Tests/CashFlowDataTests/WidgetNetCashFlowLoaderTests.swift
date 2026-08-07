import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("WidgetNetCashFlowLoader")
struct WidgetNetCashFlowLoaderTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Different time frames yield different totals on the same store")
    func rangesProduceIndependentTotals() async throws {
        let now = Date(timeIntervalSince1970: 1_720_000_000) // ~2024-07-03 UTC
        let calendar = utcCalendar
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let account = AccountEntity(
            id: "acct",
            externalID: "ext",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 0,
            balanceDate: now
        )
        context.insert(account)

        // This month income
        insertTx(
            context: context,
            account: account,
            id: "m1",
            amount: 1000,
            posted: now,
            category: SystemCategory.income.id.rawValue
        )
        // This month expense
        insertTx(
            context: context,
            account: account,
            id: "m2",
            amount: -100,
            posted: now,
            category: SystemCategory.dining.id.rawValue
        )
        // Last month income
        let lastMonthDay = calendar.date(byAdding: .month, value: -1, to: now)!
        insertTx(
            context: context,
            account: account,
            id: "lm1",
            amount: 500,
            posted: lastMonthDay,
            category: SystemCategory.income.id.rawValue
        )
        // Mid prior month expense — inside Last 30 Days + Last Month, outside This Month
        let twentyDaysAgo = calendar.date(byAdding: .day, value: -20, to: now)!
        insertTx(
            context: context,
            account: account,
            id: "lm2",
            amount: -25,
            posted: twentyDaysAgo,
            category: SystemCategory.dining.id.rawValue
        )
        // ~45 days ago expense (outside last 30 days, inside six-month custom)
        let fortyFiveDaysAgo = calendar.date(byAdding: .day, value: -45, to: now)!
        insertTx(
            context: context,
            account: account,
            id: "old1",
            amount: -50,
            posted: fortyFiveDaysAgo,
            category: SystemCategory.dining.id.rawValue
        )
        // Five months ago income (inside six-month custom, outside last 30)
        let fiveMonthsAgo = calendar.date(byAdding: .month, value: -5, to: now)!
        insertTx(
            context: context,
            account: account,
            id: "old2",
            amount: 200,
            posted: fiveMonthsAgo,
            category: SystemCategory.income.id.rawValue
        )
        // Pending — ignored
        insertTx(
            context: context,
            account: account,
            id: "pend",
            amount: -999,
            posted: now,
            category: SystemCategory.dining.id.rawValue,
            pending: true
        )
        // Transfer — excluded from contribution
        insertTx(
            context: context,
            account: account,
            id: "xfer",
            amount: -300,
            posted: now,
            category: SystemCategory.transfer.id.rawValue
        )
        try context.save()

        let loader = WidgetNetCashFlowLoader(modelContainer: container)

        let thisMonth = await loader.load(
            timeFrame: .thisMonth,
            now: now,
            calendar: calendar
        )
        let lastMonth = await loader.load(
            timeFrame: .lastMonth,
            now: now,
            calendar: calendar
        )
        let last30 = await loader.load(
            timeFrame: .last30Days,
            now: now,
            calendar: calendar
        )
        let sixMonthsStart = calendar.date(byAdding: .month, value: -6, to: now)!
        let sixMonths = await loader.load(
            timeFrame: .custom,
            customStart: sixMonthsStart,
            customEnd: now,
            now: now,
            calendar: calendar
        )

        #expect(thisMonth?.incomeTotal == 1000)
        #expect(thisMonth?.expenseTotal == 100)
        #expect(thisMonth?.net == 900)
        #expect(thisMonth?.rangeLabel == "This Month")

        #expect(lastMonth?.incomeTotal == 500)
        #expect(lastMonth?.expenseTotal == 25)
        #expect(lastMonth?.net == 475)
        #expect(lastMonth?.rangeLabel == "Last Month")

        // Last 30 includes this-month txs + mid prior-month expense, not 45 days ago
        #expect(last30?.incomeTotal == 1000)
        #expect(last30?.expenseTotal == 100 + 25)
        #expect(last30?.net == 1000 - 125)

        // Custom six months includes everything posted except pending/transfer
        #expect(sixMonths?.incomeTotal == 1000 + 500 + 200)
        #expect(sixMonths?.expenseTotal == 100 + 25 + 50)
        #expect(sixMonths?.net == (1000 + 500 + 200) - (100 + 25 + 50))

        // Independence: Home-style last-30 vs widget custom six months differ
        #expect(last30?.net != sixMonths?.net)
        #expect(thisMonth?.net != lastMonth?.net)
        #expect(thisMonth?.net != last30?.net)
    }

    @Test("Empty store returns zero totals")
    func emptyStoreZeros() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let loader = WidgetNetCashFlowLoader(modelContainer: container)
        let totals = await loader.load(timeFrame: .thisMonth)
        #expect(totals?.net == 0)
        #expect(totals?.incomeTotal == 0)
        #expect(totals?.expenseTotal == 0)
        #expect(totals?.rangeLabel == "This Month")
    }

    @Test("Unavailable App Group returns nil for default loader")
    func unavailableAppGroup() async {
        let loader = WidgetNetCashFlowLoader(appGroupID: "group.com.expensetracking.missing.for.tests")
        let totals = await loader.load(timeFrame: .thisMonth)
        #expect(totals == nil)
    }

    private func insertTx(
        context: ModelContext,
        account: AccountEntity,
        id: String,
        amount: Decimal,
        posted: Date,
        category: String,
        pending: Bool = false
    ) {
        context.insert(
            TransactionEntity(
                id: id,
                externalID: id,
                accountID: account.id,
                amount: amount,
                postedDate: posted,
                transactionDescription: id,
                categoryID: category,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: pending,
                syncKey: "\(account.externalID)|\(id)",
                account: account
            )
        )
    }
}

@Suite("NetSnapshotStore cleanup")
struct NetSnapshotStoreCleanupTests {
    @Test("Clear is safe when the snapshot file is missing")
    func clearMissingIsSafe() throws {
        let store = NetSnapshotStore(appGroupID: "group.com.expensetracking.missing.for.tests")
        try store.clear()
    }
}

@Suite("SyncCoordinator widget reload")
struct SyncCoordinatorWidgetReloadTests {
    @Test("Successful demo sync reloads the widget timeline")
    func syncReloadsWidget() async throws {
        let linking = CompositeBankLinkingService(
            demo: DemoBankLinkingService(seedSize: .standard),
            simpleFIN: SimpleFINBankLinkingService(),
            initialMode: .none
        )
        try await linking.link(withSetupToken: "demo")
        let container = try ModelContainerFactory.make(inMemory: true)
        let reloader = RecordingWidgetTimelineReloader()
        let sync = SyncCoordinator(
            modelContainer: container,
            bankLinking: linking,
            widgetTimelineReloader: reloader
        )
        _ = try await sync.syncNow()
        #expect(reloader.reloadCount == 1)
    }
}

@Suite("LocalDataResetter widget reload")
struct LocalDataResetterWidgetReloadTests {
    @Test("Wipe clears leftover snapshot and reloads the widget")
    func wipeReloadsWidget() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let reloader = RecordingWidgetTimelineReloader()
        let resetter = LocalDataResetter(
            modelContainer: container,
            widgetTimelineReloader: reloader
        )
        try await resetter.resetAll()
        #expect(reloader.reloadCount == 1)
    }
}
