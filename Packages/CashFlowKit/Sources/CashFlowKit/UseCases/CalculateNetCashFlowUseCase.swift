import Foundation

public struct NetCashFlowResult: Sendable, Equatable {
    public let net: Decimal
    public let incomeTotal: Decimal
    public let expenseTotal: Decimal
    /// Cumulative net cash flow by day within the selected range (matches the hero net at the end).
    public let dailyPoints: [DailyCashFlowPoint]

    public init(
        net: Decimal,
        incomeTotal: Decimal,
        expenseTotal: Decimal,
        dailyPoints: [DailyCashFlowPoint]
    ) {
        self.net = net
        self.incomeTotal = incomeTotal
        self.expenseTotal = expenseTotal
        self.dailyPoints = dailyPoints
    }
}

public struct DailyCashFlowPoint: Sendable, Equatable, Identifiable {
    public var id: Date { day }
    public let day: Date
    /// Running net from the start of the range through this day.
    public let net: Decimal

    public init(day: Date, net: Decimal) {
        self.day = day
        self.net = net
    }
}

public struct CalculateNetCashFlowUseCase: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func execute(
        transactions: [Transaction],
        range: CashFlowDateRange,
        now: Date = .now
    ) -> NetCashFlowResult {
        let interval = range.interval(calendar: calendar, now: now)
        var incomeTotal: Decimal = 0
        var expenseTotal: Decimal = 0
        var dailyDelta: [Date: Decimal] = [:]

        for transaction in transactions {
            guard !transaction.isPending else { continue }
            guard transaction.postedDate >= interval.start,
                  transaction.postedDate <= interval.end
            else { continue }

            let contribution = CashFlowContribution.forTransaction(transaction)
            let signed = contribution.signedAmount(of: transaction.amount)
            switch contribution {
            case .income:
                incomeTotal += abs(transaction.amount)
            case .expense:
                expenseTotal += abs(transaction.amount)
            case .none:
                break
            }

            let day = calendar.startOfDay(for: transaction.postedDate)
            dailyDelta[day, default: 0] += signed
        }

        let net = incomeTotal - expenseTotal
        let points = cumulativePoints(
            dailyDelta: dailyDelta,
            rangeStart: interval.start,
            rangeEnd: min(interval.end, now)
        )

        return NetCashFlowResult(
            net: net,
            incomeTotal: incomeTotal,
            expenseTotal: expenseTotal,
            dailyPoints: points
        )
    }

    /// Builds a day-by-day running total so the chart ends at the same net as the hero metric.
    private func cumulativePoints(
        dailyDelta: [Date: Decimal],
        rangeStart: Date,
        rangeEnd: Date
    ) -> [DailyCashFlowPoint] {
        let startDay = calendar.startOfDay(for: rangeStart)
        let endDay = calendar.startOfDay(for: rangeEnd)
        guard startDay <= endDay else { return [] }

        var points: [DailyCashFlowPoint] = []
        var running: Decimal = 0
        var day = startDay

        while day <= endDay {
            running += dailyDelta[day] ?? 0
            points.append(DailyCashFlowPoint(day: day, net: running))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return points
    }
}
