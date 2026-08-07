import Foundation
import Testing
import CashFlowKit
@testable import ExpenseTracking

@Suite("ZeroCrossingSeriesBuilder")
struct ZeroCrossingSeriesBuilderTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("All-positive series stays on the positive side")
    func allPositive() {
        let points = makePoints([10, 20, 5])
        let series = ZeroCrossingSeriesBuilder.split(points)
        #expect(series.negative.isEmpty)
        #expect(series.positive.map(\.value) == [10, 20, 5])
    }

    @Test("All-negative series stays on the negative side")
    func allNegative() {
        let points = makePoints([-10, -20, -5])
        let series = ZeroCrossingSeriesBuilder.split(points)
        #expect(series.positive.isEmpty)
        #expect(series.negative.map(\.value) == [-10, -20, -5])
    }

    @Test("Positive-to-negative crossing inserts a zero point on both series")
    func crossesDownThroughZero() {
        let points = makePoints([50, -50])
        let series = ZeroCrossingSeriesBuilder.split(points)

        #expect(series.positive.contains(where: { $0.value == 0 }))
        #expect(series.negative.contains(where: { $0.value == 0 }))
        #expect(series.positive.first?.value == 50)
        #expect(series.negative.last?.value == -50)

        let zeroDay = series.positive.last?.day
        #expect(zeroDay == series.negative.first?.day)
        // Midpoint between day 0 and day 1 when values are symmetric.
        if let zeroDay, let start = points.first?.day {
            let expected = start.addingTimeInterval(86_400 / 2)
            #expect(abs(zeroDay.timeIntervalSince(expected)) < 1)
        }
    }

    @Test("Negative-to-positive crossing uses a new segment id")
    func crossesUpThroughZero() {
        let points = makePoints([-40, 60])
        let series = ZeroCrossingSeriesBuilder.split(points)
        #expect(series.negative.first?.segmentID != series.positive.last?.segmentID)
        #expect(series.negative.contains(where: { $0.value == 0 }))
        #expect(series.positive.contains(where: { $0.value == 0 }))
    }

    @Test("Touching zero without changing sign keeps one positive segment")
    func touchZeroStayPositive() {
        let points = makePoints([40, 0, 20])
        let series = ZeroCrossingSeriesBuilder.split(points)
        #expect(series.negative.isEmpty)
        #expect(Set(series.positive.map(\.segmentID)).count == 1)
        #expect(series.positive.map(\.value) == [40, 0, 20])
    }

    @Test("Empty input yields empty series")
    func empty() {
        let series = ZeroCrossingSeriesBuilder.split([])
        #expect(series.positive.isEmpty)
        #expect(series.negative.isEmpty)
    }

    private func makePoints(_ nets: [Decimal]) -> [DailyCashFlowPoint] {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return nets.enumerated().map { index, net in
            let day = calendar.date(byAdding: .day, value: index, to: start)!
            return DailyCashFlowPoint(day: day, net: net)
        }
    }
}
