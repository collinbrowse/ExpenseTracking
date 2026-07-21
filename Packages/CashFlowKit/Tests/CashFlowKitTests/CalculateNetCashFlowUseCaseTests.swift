import Foundation
import Testing
@testable import CashFlowKit

@Suite("CalculateNetCashFlowUseCase")
struct CalculateNetCashFlowUseCaseTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private var useCase: CalculateNetCashFlowUseCase {
        CalculateNetCashFlowUseCase(calendar: calendar)
    }

    private let accountID = AccountID("acct-1")
    private let now = Date(timeIntervalSince1970: 1_720_000_000) // fixed

    private func tx(
        id: String,
        amount: Decimal,
        daysAgo: Int,
        category: SystemCategory,
        pending: Bool = false
    ) -> Transaction {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return Transaction(
            id: TransactionID(id),
            accountID: accountID,
            externalID: id,
            amount: amount,
            postedDate: date,
            description: id,
            categoryID: category.id,
            isPending: pending
        )
    }

    @Test("Income increases net; expenses decrease net")
    func incomeAndExpense() {
        let transactions = [
            tx(id: "1", amount: 3000, daysAgo: 2, category: .income),
            tx(id: "2", amount: -50, daysAgo: 1, category: .groceries),
            tx(id: "3", amount: -25, daysAgo: 1, category: .dining),
        ]
        let result = useCase.execute(
            transactions: transactions,
            range: .last30Days,
            now: now
        )
        #expect(result.incomeTotal == 3000)
        #expect(result.expenseTotal == 75)
        #expect(result.net == 2925)
    }

    @Test("Hidden, Transfer, and Credit Card Payment contribute zero")
    func excludedCategories() {
        let transactions = [
            tx(id: "1", amount: 2000, daysAgo: 1, category: .income),
            tx(id: "2", amount: -500, daysAgo: 1, category: .hidden),
            tx(id: "3", amount: -1000, daysAgo: 1, category: .transfer),
            tx(id: "4", amount: -800, daysAgo: 1, category: .creditCardPayment),
            tx(id: "5", amount: -40, daysAgo: 1, category: .shopping),
        ]
        let result = useCase.execute(
            transactions: transactions,
            range: .last30Days,
            now: now
        )
        #expect(result.incomeTotal == 2000)
        #expect(result.expenseTotal == 40)
        #expect(result.net == 1960)
    }

    @Test("Pending transactions are ignored")
    func pendingIgnored() {
        let transactions = [
            tx(id: "1", amount: 100, daysAgo: 1, category: .income),
            tx(id: "2", amount: -50, daysAgo: 1, category: .dining, pending: true),
        ]
        let result = useCase.execute(
            transactions: transactions,
            range: .last30Days,
            now: now
        )
        #expect(result.net == 100)
        #expect(result.expenseTotal == 0)
    }

    @Test("Empty set yields zero with flat cumulative series")
    func empty() {
        let result = useCase.execute(transactions: [], range: .last30Days, now: now)
        #expect(result.net == 0)
        #expect(!result.dailyPoints.isEmpty)
        #expect(result.dailyPoints.allSatisfy { $0.net == 0 })
        #expect(result.dailyPoints.last?.net == 0)
    }

    @Test("Chart points are cumulative and end at hero net")
    func cumulativeChartMatchesNet() {
        let transactions = [
            tx(id: "1", amount: 3000, daysAgo: 5, category: .income),
            tx(id: "2", amount: -100, daysAgo: 3, category: .groceries),
            tx(id: "3", amount: -50, daysAgo: 1, category: .dining),
        ]
        let result = useCase.execute(
            transactions: transactions,
            range: .last30Days,
            now: now
        )
        #expect(result.net == 2850)
        #expect(result.dailyPoints.last?.net == result.net)

        let dayIncome = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -5, to: now)!
        )
        let dayAfterIncome = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -4, to: now)!
        )
        let incomePoint = result.dailyPoints.first { $0.day == dayIncome }
        let nextPoint = result.dailyPoints.first { $0.day == dayAfterIncome }
        #expect(incomePoint?.net == 3000)
        // Flat between events — cumulative holds, does not reset to zero.
        #expect(nextPoint?.net == 3000)
    }

    @Test("Custom range excludes outside dates")
    func customRange() {
        let start = calendar.date(byAdding: .day, value: -5, to: now)!
        let end = calendar.date(byAdding: .day, value: -2, to: now)!
        let transactions = [
            tx(id: "in", amount: 100, daysAgo: 3, category: .income),
            tx(id: "out", amount: 200, daysAgo: 10, category: .income),
        ]
        let result = useCase.execute(
            transactions: transactions,
            range: .custom(start...end),
            now: now
        )
        #expect(result.net == 100)
    }

    @Test("Expense amount sign does not matter for magnitude")
    func absoluteExpense() {
        let transactions = [
            tx(id: "1", amount: 50, daysAgo: 1, category: .groceries),
            tx(id: "2", amount: -50, daysAgo: 1, category: .dining),
        ]
        let result = useCase.execute(
            transactions: transactions,
            range: .last30Days,
            now: now
        )
        #expect(result.expenseTotal == 100)
        #expect(result.net == -100)
    }
}

@Suite("MergeSyncPolicy")
struct MergeSyncPolicyTests {
    @Test("Remote wins amount; local wins edited category and description")
    func localCategoryWins() {
        let account = AccountID("a")
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 10,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "old",
            categoryID: SystemCategory.dining.id,
            userEditedCategory: true
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 20,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "new",
            categoryID: SystemCategory.groceries.id,
            userEditedCategory: false
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote)
        #expect(merged.amount == 20)
        #expect(merged.description == "old")
        #expect(merged.postedDate == remote.postedDate)
        #expect(merged.categoryID == SystemCategory.dining.id)
        #expect(merged.userEditedCategory == true)
    }

    @Test("Without user edit, remote category wins")
    func remoteCategoryWins() {
        let account = AccountID("a")
        let local = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 10,
            postedDate: Date(timeIntervalSince1970: 100),
            description: "old",
            categoryID: SystemCategory.dining.id,
            userEditedCategory: false
        )
        let remote = Transaction(
            id: TransactionID("t1"),
            accountID: account,
            externalID: "ext",
            amount: 20,
            postedDate: Date(timeIntervalSince1970: 200),
            description: "new",
            categoryID: SystemCategory.income.id
        )
        let merged = MergeSyncPolicy.merge(local: local, remote: remote)
        #expect(merged.categoryID == SystemCategory.income.id)
        #expect(merged.userEditedCategory == false)
    }
}

@Suite("SystemCategory")
struct SystemCategoryTests {
    @Test("allCategories is alphabetical by name")
    func allCategoriesAlphabetical() {
        let names = SystemCategory.allCategories.map(\.name)
        #expect(names == names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(names.first == "Auto & Transport")
        #expect(names.contains("Rent & Mortgage"))
        #expect(names.contains("Food & Dining"))
        #expect(names.contains("Health & Fitness"))
        #expect(names.contains("Travel & Vacation"))
        #expect(names.contains("Business Services"))
        #expect(names.contains("Fees & Charges"))
        #expect(names.contains("Medical"))
        #expect(names.contains("Bills & Utilities"))
    }
}

@Suite("MergeAccountSyncPolicy")
struct MergeAccountSyncPolicyTests {
    @Test("User-edited name is kept")
    func localNameWins() {
        let resolved = MergeAccountSyncPolicy.resolvedName(
            localName: "Vacation Fund",
            localUserEditedName: true,
            remoteName: "Checking"
        )
        #expect(resolved.name == "Vacation Fund")
        #expect(resolved.userEditedName == true)
    }

    @Test("Without user edit, remote name wins")
    func remoteNameWins() {
        let resolved = MergeAccountSyncPolicy.resolvedName(
            localName: "Old",
            localUserEditedName: false,
            remoteName: "Checking"
        )
        #expect(resolved.name == "Checking")
        #expect(resolved.userEditedName == false)
    }
}

@Suite("CashFlowDateRange")
struct CashFlowDateRangeTests {
    @Test("last30Days spans roughly 30 days")
    func last30() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let interval = CashFlowDateRange.last30Days.interval(calendar: calendar, now: now)
        let days = calendar.dateComponents([.day], from: interval.start, to: interval.end).day
        #expect(days == 30)
    }
}
