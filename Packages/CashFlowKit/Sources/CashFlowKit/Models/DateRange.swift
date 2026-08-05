import Foundation

public enum CashFlowDateRange: Hashable, Sendable {
    case month(Date)
    case last30Days
    case lastYear
    case custom(ClosedRange<Date>)

    public func interval(calendar: Calendar = .current, now: Date = .now) -> DateInterval {
        switch self {
        case .month(let date):
            // Month-to-date when `date` is in the current month; otherwise the full month.
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
                ?? date
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)
                ?? date
            let end = calendar.isDate(date, equalTo: now, toGranularity: .month)
                ? min(endOfMonth, now)
                : endOfMonth
            return DateInterval(start: start, end: max(start, end))
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .lastYear:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .custom(let range):
            return DateInterval(start: range.lowerBound, end: range.upperBound)
        }
    }

    public func contains(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> Bool {
        let interval = interval(calendar: calendar, now: now)
        return date >= interval.start && date <= interval.end
    }
}
