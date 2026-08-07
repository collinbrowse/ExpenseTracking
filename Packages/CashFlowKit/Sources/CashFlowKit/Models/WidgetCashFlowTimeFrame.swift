import Foundation

/// Home-screen widget time-frame options (Year stays app-only).
public enum WidgetCashFlowTimeFrame: String, CaseIterable, Sendable, Codable, Equatable {
    case thisMonth
    case lastMonth
    case last30Days
    case custom

    /// WidgetKit configuration kind shared by the app (reload) and extension.
    public static let widgetKind = "CashFlowWidget"

    public func dateRange(
        customStart: Date?,
        customEnd: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CashFlowDateRange {
        switch self {
        case .thisMonth:
            return .month(now)
        case .lastMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return .month(previous)
        case .last30Days:
            return .last30Days
        case .custom:
            guard let customStart, let customEnd else {
                return .month(now)
            }
            let start = min(customStart, customEnd)
            let end = max(customStart, customEnd)
            return .custom(start...end)
        }
    }

    public func rangeLabel(
        customStart: Date?,
        customEnd: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        switch self {
        case .thisMonth:
            return "This Month"
        case .lastMonth:
            return "Last Month"
        case .last30Days:
            return "Last 30 Days"
        case .custom:
            guard let customStart, let customEnd else {
                return "This Month"
            }
            let start = min(customStart, customEnd)
            let end = max(customStart, customEnd)
            let style = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
            if calendar.isDate(start, inSameDayAs: end) {
                return start.formatted(style)
            }
            return "\(start.formatted(style)) – \(end.formatted(style))"
        }
    }
}
