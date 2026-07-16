import SwiftUI
import Charts
import CashFlowKit

/// Interactive cumulative net chart with press-and-drag scrubbing (Apple Charts pattern).
struct NetCashFlowChartView: View {
    let points: [DailyCashFlowPoint]
    let accentPositive: Bool
    let rangeTitle: String
    let endNet: Decimal
    /// Change to replay the entrance animation (e.g. after first data load).
    var animationToken: Int = 0

    @State private var rawSelectedDate: Date?
    /// 0…1 left-to-right reveal of the plot only (axes stay fully visible).
    @State private var revealProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        accentPositive ? Theme.positive : Color.primary
    }

    private var selectedPoint: DailyCashFlowPoint? {
        guard revealProgress >= 1, let rawSelectedDate else { return nil }
        return nearestPoint(to: rawSelectedDate)
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
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Net", doubleValue(point.net))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)

                LineMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Net", doubleValue(point.net))
                )
                .foregroundStyle(accent)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.day, unit: .day))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .zIndex(-1)
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        selectionCallout(for: selectedPoint)
                    }

                PointMark(
                    x: .value("Selected", selectedPoint.day, unit: .day),
                    y: .value("Net", doubleValue(selectedPoint.net))
                )
                .symbol {
                    Circle()
                        .strokeBorder(.background, lineWidth: 2)
                        .background(Circle().fill(accent))
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

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
