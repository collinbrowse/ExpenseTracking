import Foundation

/// Home-screen widget time-frame options (Year stays app-only).
public enum WidgetCashFlowTimeFrame: String, CaseIterable, Sendable, Codable, Equatable {
    case thisMonth
    case previousMonth
    case last30Days
    case previous3Months
    case last90Days
    case previous6Months
    case last180Days

    /// WidgetKit configuration kind shared by the app (reload) and extension.
    public static let widgetKind = "CashFlowWidget"

    public func dateRange(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CashFlowDateRange {
        switch self {
        case .thisMonth:
            return .month(now)
        case .previousMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return .month(previous)
        case .last30Days:
            return .last30Days
        case .previous3Months:
            return Self.previousCalendarMonths(count: 3, now: now, calendar: calendar)
        case .last90Days:
            return Self.lastDays(90, now: now, calendar: calendar)
        case .previous6Months:
            return Self.previousCalendarMonths(count: 6, now: now, calendar: calendar)
        case .last180Days:
            return Self.lastDays(180, now: now, calendar: calendar)
        }
    }

    public func rangeLabel() -> String {
        switch self {
        case .thisMonth:
            return "This Month"
        case .previousMonth:
            return "Previous Month"
        case .last30Days:
            return "Last 30 Days"
        case .previous3Months:
            return "Previous 3 Months"
        case .last90Days:
            return "Last 90 Days"
        case .previous6Months:
            return "Previous 6 Months"
        case .last180Days:
            return "Last 180 Days"
        }
    }

    /// Full calendar months immediately before the current month (excludes this month).
    private static func previousCalendarMonths(
        count: Int,
        now: Date,
        calendar: Calendar
    ) -> CashFlowDateRange {
        let startOfCurrentMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let start = calendar.date(byAdding: .month, value: -count, to: startOfCurrentMonth) ?? now
        let end = calendar.date(byAdding: .second, value: -1, to: startOfCurrentMonth) ?? now
        return .custom(start...max(start, end))
    }

    private static func lastDays(
        _ days: Int,
        now: Date,
        calendar: Calendar
    ) -> CashFlowDateRange {
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? now
        return .custom(start...now)
    }
}
