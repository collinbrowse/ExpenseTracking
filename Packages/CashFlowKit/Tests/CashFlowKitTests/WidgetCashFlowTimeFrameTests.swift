import Foundation
import Testing
import CashFlowKit

@Suite("WidgetCashFlowTimeFrame")
struct WidgetCashFlowTimeFrameTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("This Month maps to current month-to-date and label")
    func thisMonth() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let range = WidgetCashFlowTimeFrame.thisMonth.dateRange(now: now, calendar: utcCalendar)
        let interval = range.interval(calendar: utcCalendar, now: now)
        let monthStart = utcCalendar.date(
            from: utcCalendar.dateComponents([.year, .month], from: now)
        )!
        #expect(interval.start == monthStart)
        #expect(interval.end == now)
        #expect(WidgetCashFlowTimeFrame.thisMonth.rangeLabel() == "This Month")
    }

    @Test("Previous Month is the full prior calendar month")
    func previousMonthFullPriorMonth() {
        let now = Date(timeIntervalSince1970: 1_720_000_000) // 2024-07-03-ish UTC
        let range = WidgetCashFlowTimeFrame.previousMonth.dateRange(now: now, calendar: utcCalendar)
        let interval = range.interval(calendar: utcCalendar, now: now)
        let previous = utcCalendar.date(byAdding: .month, value: -1, to: now)!
        let expectedStart = utcCalendar.date(
            from: utcCalendar.dateComponents([.year, .month], from: previous)
        )!
        let expectedEnd = utcCalendar.date(
            byAdding: DateComponents(month: 1, second: -1),
            to: expectedStart
        )!
        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
        #expect(interval.end < now)
        #expect(WidgetCashFlowTimeFrame.previousMonth.rangeLabel() == "Previous Month")
    }

    @Test("Last 30 Days matches CashFlowDateRange.last30Days")
    func last30Days() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let range = WidgetCashFlowTimeFrame.last30Days.dateRange(now: now, calendar: utcCalendar)
        let interval = range.interval(calendar: utcCalendar, now: now)
        let expected = CashFlowDateRange.last30Days.interval(calendar: utcCalendar, now: now)
        #expect(interval.start == expected.start)
        #expect(interval.end == expected.end)
        #expect(WidgetCashFlowTimeFrame.last30Days.rangeLabel() == "Last 30 Days")
    }

    @Test("Previous 3 Months is three full calendar months before this month")
    func previous3Months() {
        let now = Date(timeIntervalSince1970: 1_720_000_000) // 2024-07-03 UTC
        let range = WidgetCashFlowTimeFrame.previous3Months.dateRange(
            now: now,
            calendar: utcCalendar
        )
        let interval = range.interval(calendar: utcCalendar, now: now)
        let startOfJuly = utcCalendar.date(
            from: utcCalendar.dateComponents([.year, .month], from: now)
        )!
        let expectedStart = utcCalendar.date(byAdding: .month, value: -3, to: startOfJuly)!
        let expectedEnd = utcCalendar.date(byAdding: .second, value: -1, to: startOfJuly)!
        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
        #expect(WidgetCashFlowTimeFrame.previous3Months.rangeLabel() == "Previous 3 Months")
    }

    @Test("Previous 6 Months is six full calendar months before this month")
    func previous6Months() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let range = WidgetCashFlowTimeFrame.previous6Months.dateRange(
            now: now,
            calendar: utcCalendar
        )
        let interval = range.interval(calendar: utcCalendar, now: now)
        let startOfJuly = utcCalendar.date(
            from: utcCalendar.dateComponents([.year, .month], from: now)
        )!
        let expectedStart = utcCalendar.date(byAdding: .month, value: -6, to: startOfJuly)!
        let expectedEnd = utcCalendar.date(byAdding: .second, value: -1, to: startOfJuly)!
        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
        #expect(WidgetCashFlowTimeFrame.previous6Months.rangeLabel() == "Previous 6 Months")
    }

    @Test("Last 90 Days is a rolling window ending now")
    func last90Days() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let range = WidgetCashFlowTimeFrame.last90Days.dateRange(now: now, calendar: utcCalendar)
        let interval = range.interval(calendar: utcCalendar, now: now)
        let expectedStart = utcCalendar.date(byAdding: .day, value: -90, to: now)!
        #expect(interval.start == expectedStart)
        #expect(interval.end == now)
        #expect(WidgetCashFlowTimeFrame.last90Days.rangeLabel() == "Last 90 Days")
    }

    @Test("Last 180 Days is a rolling window ending now")
    func last180Days() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let range = WidgetCashFlowTimeFrame.last180Days.dateRange(now: now, calendar: utcCalendar)
        let interval = range.interval(calendar: utcCalendar, now: now)
        let expectedStart = utcCalendar.date(byAdding: .day, value: -180, to: now)!
        #expect(interval.start == expectedStart)
        #expect(interval.end == now)
        #expect(WidgetCashFlowTimeFrame.last180Days.rangeLabel() == "Last 180 Days")
    }

    @Test("Widget kind constant stays stable for WidgetCenter reloads")
    func widgetKind() {
        #expect(WidgetCashFlowTimeFrame.widgetKind == "CashFlowWidget")
    }
}

@Suite("CashFlowCurrencyFormatting")
struct CashFlowCurrencyFormattingTests {
    @Test("Signed net and widget income/expense rows")
    func signedRows() {
        #expect(CashFlowCurrencyFormatting.signedUSD(12.5).hasPrefix("+"))
        #expect(CashFlowCurrencyFormatting.signedUSD(-12.5).hasPrefix("−"))
        #expect(CashFlowCurrencyFormatting.signedUSD(0) == CashFlowCurrencyFormatting.usd(0))
        #expect(CashFlowCurrencyFormatting.signedIncomeUSD(100).hasPrefix("+"))
        #expect(CashFlowCurrencyFormatting.signedExpenseUSD(100).hasPrefix("−"))
        #expect(CashFlowCurrencyFormatting.signedExpenseUSD(0).hasPrefix("−"))
    }
}
