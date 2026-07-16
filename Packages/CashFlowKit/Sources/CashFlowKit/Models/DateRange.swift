import Foundation

public enum CashFlowDateRange: Hashable, Sendable {
    case month(Date)
    case last30Days
    case lastYear
    case custom(ClosedRange<Date>)

    public func interval(calendar: Calendar = .current, now: Date = .now) -> DateInterval {
        switch self {
        case .month(let date):
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
                ?? date
            let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)
                ?? date
            return DateInterval(start: start, end: end)
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
