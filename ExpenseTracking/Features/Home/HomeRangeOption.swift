import Foundation
import CashFlowKit

enum HomeRangeOption: String, CaseIterable, Identifiable {
    case month
    case last30Days
    case lastYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "Month"
        case .last30Days: "30 Days"
        case .lastYear: "Year"
        case .custom: "Custom"
        }
    }

    func dateRange(customStart: Date, customEnd: Date) -> CashFlowDateRange {
        switch self {
        case .month: .month(.now)
        case .last30Days: .last30Days
        case .lastYear: .lastYear
        case .custom:
            .custom(min(customStart, customEnd)...max(customStart, customEnd))
        }
    }
}
