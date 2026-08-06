import Foundation

/// How far back the user wants SimpleFIN history imported.
public enum HistoryLookbackYears: Int, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case ninetyDays = 0
    case one = 1
    case two = 2
    case five = 5

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .ninetyDays: return "90 days"
        case .one: return "1 year"
        case .two: return "2 years"
        case .five: return "5 years (bank-dependent)"
        }
    }

    public var startDate: Date {
        let calendar = Calendar.current
        let now = Date.now
        switch self {
        case .ninetyDays:
            return calendar.date(byAdding: .day, value: -90, to: now) ?? now
        case .one:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        case .two:
            return calendar.date(byAdding: .year, value: -2, to: now) ?? now
        case .five:
            return calendar.date(byAdding: .year, value: -5, to: now) ?? now
        }
    }

    public static let `default`: HistoryLookbackYears = .two
}

/// Durable multi-day status for history backfill and title enrichment.
public struct HistoryImportStatus: Equatable, Sendable {
    public let lookback: HistoryLookbackYears
    public let earliestFetchedDate: Date?
    public let targetStartDate: Date
    public let historyComplete: Bool
    public let lastBackfillAdvanceAt: Date?
    public let untitledCount: Int
    public let totalPostedCount: Int
    public let distinctMerchantLookupsRemaining: Int

    public init(
        lookback: HistoryLookbackYears,
        earliestFetchedDate: Date?,
        targetStartDate: Date,
        historyComplete: Bool,
        lastBackfillAdvanceAt: Date?,
        untitledCount: Int,
        totalPostedCount: Int,
        distinctMerchantLookupsRemaining: Int
    ) {
        self.lookback = lookback
        self.earliestFetchedDate = earliestFetchedDate
        self.targetStartDate = targetStartDate
        self.historyComplete = historyComplete
        self.lastBackfillAdvanceAt = lastBackfillAdvanceAt
        self.untitledCount = untitledCount
        self.totalPostedCount = totalPostedCount
        self.distinctMerchantLookupsRemaining = distinctMerchantLookupsRemaining
    }

    /// 0...1 coverage of the requested lookback window, or 1 when complete / bank ran dry.
    public var historyFraction: Double {
        if historyComplete { return 1 }
        guard let earliest = earliestFetchedDate else { return 0 }
        let total = Date.now.timeIntervalSince(targetStartDate)
        guard total > 0 else { return 1 }
        let covered = Date.now.timeIntervalSince(earliest)
        return min(1, max(0, covered / total))
    }

    public var titledFraction: Double {
        guard totalPostedCount > 0 else { return 1 }
        let titled = totalPostedCount - untitledCount
        return min(1, max(0, Double(titled) / Double(totalPostedCount)))
    }

    public var needsTitleCleanup: Bool { untitledCount > 0 }

    public var isStalled: Bool {
        guard !historyComplete || needsTitleCleanup else { return false }
        guard let last = lastBackfillAdvanceAt else { return false }
        return Date.now.timeIntervalSince(last) > 48 * 60 * 60
    }

    public var continuationCopy: String {
        if historyComplete && !needsTitleCleanup {
            return "Up to date"
        }
        if isStalled {
            return "Open the app to continue"
        }
        return "Continues automatically"
    }

    public func earliestFetchedDisplay(formatter: DateFormatter) -> String? {
        guard let earliestFetchedDate else { return nil }
        return formatter.string(from: earliestFetchedDate)
    }

    /// Keeps the idle "N titles left" snapshot while refreshing bank-history fields.
    public func preservingTitleBacklog(from other: HistoryImportStatus) -> HistoryImportStatus {
        HistoryImportStatus(
            lookback: lookback,
            earliestFetchedDate: earliestFetchedDate,
            targetStartDate: targetStartDate,
            historyComplete: historyComplete,
            lastBackfillAdvanceAt: lastBackfillAdvanceAt,
            untitledCount: other.untitledCount,
            totalPostedCount: other.totalPostedCount,
            distinctMerchantLookupsRemaining: other.distinctMerchantLookupsRemaining
        )
    }
}

public enum HistoryImportStatusBuilding: Sendable {
    public static func build(
        lookback: HistoryLookbackYears,
        earliestFetchedDate: Date?,
        historyComplete: Bool,
        lastBackfillAdvanceAt: Date?,
        untitledCount: Int,
        totalPostedCount: Int,
        distinctMerchantLookupsRemaining: Int,
        now: Date = .now
    ) -> HistoryImportStatus {
        HistoryImportStatus(
            lookback: lookback,
            earliestFetchedDate: earliestFetchedDate,
            targetStartDate: lookback.startDate,
            historyComplete: historyComplete,
            lastBackfillAdvanceAt: lastBackfillAdvanceAt,
            untitledCount: untitledCount,
            totalPostedCount: totalPostedCount,
            distinctMerchantLookupsRemaining: distinctMerchantLookupsRemaining
        )
    }
}
