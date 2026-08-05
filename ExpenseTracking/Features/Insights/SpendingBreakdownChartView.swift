import SwiftUI
import Charts
import CashFlowKit

/// Horizontal bar chart for ranked spending slices (category or tag).
struct SpendingBreakdownChartView: View {
    let rows: [InsightsSliceRow]

    var body: some View {
        Chart(rows) { row in
            BarMark(
                x: .value("Amount", doubleValue(row.total)),
                y: .value("Name", row.name)
            )
            .foregroundStyle(Color.accentColor.opacity(0.85))
            .accessibilityLabel(row.name)
            .accessibilityValue(row.amountText)
        }
        .chartXAxis {
            AxisMarks(position: .bottom) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(CurrencyFormatting.usd(Decimal(amount)))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(name)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(height: chartHeight)
        .accessibilityIdentifier("insights.chart")
    }

    private var chartHeight: CGFloat {
        CGFloat(max(rows.count, 1)) * 36 + 24
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
