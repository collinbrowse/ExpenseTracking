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
        let range = WidgetCashFlowTimeFrame.thisMonth.dateRange(
            customStart: nil,
            customEnd: nil,
            now: now,
            calendar: utcCalendar
        )
        let interval = range.interval(calendar: utcCalendar, now: now)
        let monthStart = utcCalendar.date(
            from: utcCalendar.dateComponents([.year, .month], from: now)
        )!
        #expect(interval.start == monthStart)
        #expect(interval.end == now)
        #expect(
            WidgetCashFlowTimeFrame.thisMonth.rangeLabel(
                customStart: nil,
                customEnd: nil,
                now: now,
                calendar: utcCalendar
            ) == "This Month"
        )
    }

    @Test("Last Month is the full prior calendar month")
    func lastMonthFullPriorMonth() {
        let now = Date(timeIntervalSince1970: 1_720_000_000) // 2024-07-03-ish UTC
        let range = WidgetCashFlowTimeFrame.lastMonth.dateRange(
            customStart: nil,
            customEnd: nil,
            now: now,
            calendar: utcCalendar
        )
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
        #expect(
            WidgetCashFlowTimeFrame.lastMonth.rangeLabel(
                customStart: nil,
                customEnd: nil,
                now: now,
                calendar: utcCalendar
            ) == "Last Month"
        )
    }

    @Test("Last 30 Days matches CashFlowDateRange.last30Days")
    func last30Days() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let range = WidgetCashFlowTimeFrame.last30Days.dateRange(
            customStart: nil,
            customEnd: nil,
            now: now,
            calendar: utcCalendar
        )
        let interval = range.interval(calendar: utcCalendar, now: now)
        let expected = CashFlowDateRange.last30Days.interval(calendar: utcCalendar, now: now)
        #expect(interval.start == expected.start)
        #expect(interval.end == expected.end)
        #expect(
            WidgetCashFlowTimeFrame.last30Days.rangeLabel(
                customStart: nil,
                customEnd: nil,
                now: now,
                calendar: utcCalendar
            ) == "Last 30 Days"
        )
    }

    @Test("Custom normalizes reversed dates and formats a span label")
    func customNormalizesOrder() {
        let calendar = utcCalendar
        let end = Date(timeIntervalSince1970: 1_720_000_000)
        let start = calendar.date(byAdding: .day, value: -10, to: end)!
        // Pass reversed.
        let range = WidgetCashFlowTimeFrame.custom.dateRange(
            customStart: end,
            customEnd: start,
            now: end,
            calendar: calendar
        )
        let interval = range.interval(calendar: calendar, now: end)
        #expect(interval.start == start)
        #expect(interval.end == end)

        let label = WidgetCashFlowTimeFrame.custom.rangeLabel(
            customStart: end,
            customEnd: start,
            now: end,
            calendar: calendar
        )
        #expect(label.contains("–"))
        #expect(!label.isEmpty)
    }

    @Test("Custom with equal dates is a single-day range")
    func customSingleDay() {
        let day = Date(timeIntervalSince1970: 1_720_000_000)
        let range = WidgetCashFlowTimeFrame.custom.dateRange(
            customStart: day,
            customEnd: day,
            now: day,
            calendar: utcCalendar
        )
        let interval = range.interval(calendar: utcCalendar, now: day)
        #expect(interval.start == day)
        #expect(interval.end == day)
        let label = WidgetCashFlowTimeFrame.custom.rangeLabel(
            customStart: day,
            customEnd: day,
            now: day,
            calendar: utcCalendar
        )
        #expect(!label.contains("–"))
    }

    @Test("Custom with missing dates falls back to This Month")
    func customMissingFallsBack() {
        let now = Date(timeIntervalSince1970: 1_720_000_000)
        let range = WidgetCashFlowTimeFrame.custom.dateRange(
            customStart: nil,
            customEnd: nil,
            now: now,
            calendar: utcCalendar
        )
        #expect(range == .month(now))
        #expect(
            WidgetCashFlowTimeFrame.custom.rangeLabel(
                customStart: nil,
                customEnd: nil,
                now: now,
                calendar: utcCalendar
            ) == "This Month"
        )
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
