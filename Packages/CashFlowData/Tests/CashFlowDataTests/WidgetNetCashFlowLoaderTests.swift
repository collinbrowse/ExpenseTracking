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
        // Use Calendar.current — fetchPosted resolves ranges with the system calendar.
        let now = Date(timeIntervalSince1970: 1_720_000_000) // ~2024-07-03 UTC
        let calendar = Calendar.current
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
        // Early prior month income — inside Last Month, outside Last 30 Days
        // (now − 30d lands on the same calendar day last month; stay earlier).
        let lastMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: -1, to: now)!)
        )!
        insertTx(
            context: context,
            account: account,
            id: "lm1",
            amount: 500,
            posted: lastMonthStart,
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
        // ~45 days ago expense (outside last 30 days, inside last 90 / previous 6 months)
        let fortyFiveDaysAgo = calendar.date(byAdding: .day, value: -45, to: now)!
        insertTx(
            context: context,
            account: account,
            id: "old1",
            amount: -50,
            posted: fortyFiveDaysAgo,
            category: SystemCategory.dining.id.rawValue
        )
        // Five months ago income (inside previous 6 months, outside last 90)
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

        let thisMonth = try #require(await loader.load(
            timeFrame: .thisMonth,
            now: now,
            calendar: calendar
        ))
        let previousMonth = try #require(await loader.load(
            timeFrame: .previousMonth,
            now: now,
            calendar: calendar
        ))
        let last30 = try #require(await loader.load(
            timeFrame: .last30Days,
            now: now,
            calendar: calendar
        ))
        let previous6 = try #require(await loader.load(
            timeFrame: .previous6Months,
            now: now,
            calendar: calendar
        ))
        let last90 = try #require(await loader.load(
            timeFrame: .last90Days,
            now: now,
            calendar: calendar
        ))

        #expect(thisMonth.incomeTotal == Decimal(1000))
        #expect(thisMonth.expenseTotal == Decimal(100))
        #expect(thisMonth.net == Decimal(900))
        #expect(thisMonth.rangeLabel == "This Month")

        #expect(previousMonth.incomeTotal == Decimal(500))
        #expect(previousMonth.expenseTotal == Decimal(25))
        #expect(previousMonth.net == Decimal(475))
        #expect(previousMonth.rangeLabel == "Previous Month")

        // Last 30 includes this-month txs + mid prior-month expense, not early-June income
        #expect(last30.incomeTotal == Decimal(1000))
        #expect(last30.expenseTotal == Decimal(125))
        #expect(last30.net == Decimal(875))

        // Previous 6 Months = full months before July (Jan–Jun): excludes this-month txs
        #expect(previous6.incomeTotal == Decimal(700))
        #expect(previous6.expenseTotal == Decimal(75))
        #expect(previous6.net == Decimal(625))
        #expect(previous6.rangeLabel == "Previous 6 Months")

        // Last 90 Days includes this month + prior-month txs + 45d expense; not 5-month-old income
        #expect(last90.incomeTotal == Decimal(1500))
        #expect(last90.expenseTotal == Decimal(175))
        #expect(last90.net == Decimal(1325))
        #expect(last90.rangeLabel == "Last 90 Days")

        #expect(previous6.net != last90.net)
        #expect(thisMonth.net != previousMonth.net)
        #expect(thisMonth.net != last30.net)
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

    @Test("Empty App Group id returns nil for default loader")
    func emptyAppGroupID() async {
        // `containerURL` is nil for an empty identifier; do not open a local fallback store.
        let loader = WidgetNetCashFlowLoader(appGroupID: "")
        let totals = await loader.load(timeFrame: .thisMonth)
        #expect(totals == nil)
    }

    @Test("makeSharedStoreIfAvailable returns nil when the group is unavailable")
    func sharedStoreNilWhenUnavailable() {
        #expect(ModelContainerFactory.makeSharedStoreIfAvailable(appGroupID: "") == nil)
        #expect(ModelContainerFactory.isAppGroupAvailable("") == false)
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
