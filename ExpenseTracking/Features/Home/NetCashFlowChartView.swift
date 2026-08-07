import SwiftUI
import Charts
import CashFlowKit

/// Interactive cumulative net chart with press-and-drag scrubbing (Apple Charts pattern).
/// Line and area flip green/red at y = 0, including mid-segment zero crossings.
struct NetCashFlowChartView: View {
    let points: [DailyCashFlowPoint]
    let rangeTitle: String
    let endNet: Decimal
    /// Change to replay the entrance animation (e.g. after first data load).
    var animationToken: Int = 0

    @State private var rawSelectedDate: Date?
    /// 0…1 left-to-right reveal of the plot only (axes stay fully visible).
    @State private var revealProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRevealComplete: Bool {
        revealProgress >= 0.999
    }

    private var selectedPoint: DailyCashFlowPoint? {
        guard isRevealComplete, let rawSelectedDate else { return nil }
        return nearestPoint(to: rawSelectedDate)
    }

    private var selectedAccent: Color {
        guard let selectedPoint else { return Theme.positive }
        return chartColor(for: selectedPoint.net)
    }

    private var signedSeries: (positive: [PlotPoint], negative: [PlotPoint]) {
        ZeroCrossingSeriesBuilder.split(points)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map { doubleValue($0.net) }
        let minY = min(values.min() ?? 0, 0)
        let maxY = max(values.max() ?? 0, 0)
        if minY == maxY {
            return (minY - 1)...(maxY + 1)
        }
        let padding = (maxY - minY) * 0.08
        return (minY - padding)...(maxY + padding)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Callout lives outside the chart so the plot reveal mask cannot clip it.
            ZStack {
                if let selectedPoint {
                    selectionCallout(for: selectedPoint)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .accessibilityHidden(true)

            Chart {
                ForEach(signedSeries.positive) { point in
                    AreaMark(
                        x: .value("Day", point.day),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Net", point.value),
                        series: .value("Segment", "pos-\(point.segmentID)")
                    )
                    .foregroundStyle(Theme.positive.opacity(0.28))
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Net", point.value),
                        series: .value("Segment", "pos-\(point.segmentID)")
                    )
                    .foregroundStyle(Theme.positive)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                ForEach(signedSeries.negative) { point in
                    AreaMark(
                        x: .value("Day", point.day),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Net", point.value),
                        series: .value("Segment", "neg-\(point.segmentID)")
                    )
                    .foregroundStyle(Theme.chartNegative.opacity(0.28))
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Net", point.value),
                        series: .value("Segment", "neg-\(point.segmentID)")
                    )
                    .foregroundStyle(Theme.chartNegative)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected", selectedPoint.day, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .zIndex(-1)

                    PointMark(
                        x: .value("Selected", selectedPoint.day, unit: .day),
                        y: .value("Net", doubleValue(selectedPoint.net))
                    )
                    .symbol {
                        Circle()
                            .strokeBorder(.background, lineWidth: 2)
                            .background(Circle().fill(selectedAccent))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXSelection(value: $rawSelectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(CurrencyFormatting.signedUSD(Decimal(number)))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea.mask {
                    GeometryReader { geometry in
                        Rectangle()
                            .frame(width: max(geometry.size.width * revealProgress, 0))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 200)
        }
        .accessibilityIdentifier("home.chart")
        .accessibilityLabel(
            "Cumulative net cash flow over \(rangeTitle), ending at \(CurrencyFormatting.signedUSD(endNet)). Press and drag to inspect values."
        )
        .accessibilityValue(selectionAccessibilityValue)
        .sensoryFeedback(.selection, trigger: selectedPoint?.day) { old, new in
            !reduceMotion && old != new && new != nil
        }
        .onAppear {
            playEntranceAnimation()
        }
        .onChange(of: animationToken) { _, _ in
            playEntranceAnimation()
        }
    }

    @ViewBuilder
    private func selectionCallout(for point: DailyCashFlowPoint) -> some View {
        ChartSelectionCallout(net: point.net, date: point.day)
    }

    private var selectionAccessibilityValue: String {
        guard let selectedPoint else {
            return "No day selected"
        }
        return "\(selectedPoint.day.formatted(.dateTime.month().day())), \(CurrencyFormatting.signedUSD(selectedPoint.net))"
    }

    private func playEntranceAnimation() {
        rawSelectedDate = nil
        if reduceMotion {
            revealProgress = 1
            return
        }

        revealProgress = 0
        withAnimation(.easeInOut(duration: 0.85)) {
            revealProgress = 1
        }
    }

    private func nearestPoint(to date: Date) -> DailyCashFlowPoint? {
        guard !points.isEmpty else { return nil }
        return points.min(by: {
            abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date))
        })
    }

    private func chartColor(for value: Decimal) -> Color {
        if value > 0 { return Theme.positive }
        if value < 0 { return Theme.chartNegative }
        return Color.primary
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

// MARK: - Zero crossing series

/// Plottable point used after splitting the cumulative series at y = 0.
struct PlotPoint: Identifiable, Hashable {
    let id: String
    let day: Date
    let value: Double
    /// Contiguous segment so Charts does not connect across a gap / sign flip.
    let segmentID: Int
}

enum ZeroCrossingSeriesBuilder {
    /// Splits cumulative daily points into positive and negative plot series,
    /// inserting interpolated zero crossings so color can change mid-segment.
    static func split(_ points: [DailyCashFlowPoint]) -> (positive: [PlotPoint], negative: [PlotPoint]) {
        var positive: [PlotPoint] = []
        var negative: [PlotPoint] = []
        var segmentID = 0

        func append(_ day: Date, _ value: Double, intoPositive: Bool) {
            let point = PlotPoint(
                id: "\(segmentID)-\(day.timeIntervalSinceReferenceDate)-\(value)",
                day: day,
                value: value,
                segmentID: segmentID
            )
            if intoPositive {
                positive.append(point)
            } else {
                negative.append(point)
            }
        }

        guard let first = points.first else { return ([], []) }

        let firstValue = NSDecimalNumber(decimal: first.net).doubleValue
        append(first.day, firstValue, intoPositive: firstValue >= 0)

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let previousValue = NSDecimalNumber(decimal: previous.net).doubleValue
            let currentValue = NSDecimalNumber(decimal: current.net).doubleValue

            let crossed =
                (previousValue > 0 && currentValue < 0) ||
                (previousValue < 0 && currentValue > 0)

            if crossed {
                let zeroDay = interpolatedZeroCrossing(
                    from: previous.day, previousValue: previousValue,
                    to: current.day, currentValue: currentValue
                )
                let wasPositive = previousValue > 0
                append(zeroDay, 0, intoPositive: wasPositive)
                segmentID += 1
                append(zeroDay, 0, intoPositive: !wasPositive)
                append(current.day, currentValue, intoPositive: !wasPositive)
                continue
            }

            if currentValue == 0 {
                // Touch zero without crossing — stay on the previous side.
                append(current.day, 0, intoPositive: previousValue >= 0)
                continue
            }

            if previousValue == 0 {
                // Leaving zero: if the new side differs from where the zero was parked,
                // open a fresh segment on the new side (zero acts as the hinge).
                let lastPositiveZero = positive.last.flatMap { $0.value == 0 ? $0.day : nil }
                let lastNegativeZero = negative.last.flatMap { $0.value == 0 ? $0.day : nil }
                let zeroParkedPositive: Bool = {
                    switch (lastPositiveZero, lastNegativeZero) {
                    case let (p?, n?):
                        return p >= n
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return currentValue > 0
                    }
                }()

                let goingPositive = currentValue > 0
                if zeroParkedPositive != goingPositive {
                    segmentID += 1
                    append(previous.day, 0, intoPositive: goingPositive)
                }
                append(current.day, currentValue, intoPositive: goingPositive)
                continue
            }

            // Same-sign continuation.
            append(current.day, currentValue, intoPositive: currentValue > 0)
        }

        return (positive, negative)
    }

    private static func interpolatedZeroCrossing(
        from start: Date,
        previousValue: Double,
        to end: Date,
        currentValue: Double
    ) -> Date {
        let delta = currentValue - previousValue
        guard delta != 0 else { return end }
        let t = -previousValue / delta
        let clamped = min(max(t, 0), 1)
        let interval = end.timeIntervalSince(start)
        return start.addingTimeInterval(interval * clamped)
    }
}
