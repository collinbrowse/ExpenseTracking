import Foundation
import CashFlowKit

enum TransactionDateFilterOption: String, CaseIterable, Identifiable {
    case all
    case month
    case last30Days
    case lastYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .month: "Month"
        case .last30Days: "30 Days"
        case .lastYear: "Year"
        case .custom: "Custom"
        }
    }

    /// `nil` means no date bound — paginate through the full history.
    func dateRange(customStart: Date, customEnd: Date) -> CashFlowDateRange? {
        switch self {
        case .all: nil
        case .month: .month(.now)
        case .last30Days: .last30Days
        case .lastYear: .lastYear
        case .custom:
            .custom(min(customStart, customEnd)...max(customStart, customEnd))
        }
    }

    init(homeRange: HomeRangeOption) {
        switch homeRange {
        case .month: self = .month
        case .last30Days: self = .last30Days
        case .lastYear: self = .lastYear
        case .custom: self = .custom
        }
    }
}
