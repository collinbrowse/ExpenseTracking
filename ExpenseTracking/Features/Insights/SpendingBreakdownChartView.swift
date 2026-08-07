import SwiftUI
import Charts
import CashFlowKit

/// Interactive spending pie chart with press-and-drag angle selection.
/// Dollar amounts appear in a callout while scrubbing; legend lives below in InsightsView.
struct SpendingBreakdownChartView: View {
    let rows: [InsightsSliceRow]

    @State private var selectedAngle: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rowIDs: [String] {
        rows.map(\.id)
    }

    private var selectedRow: InsightsSliceRow? {
        guard let selectedAngle else { return nil }
        var cumulative: Double = 0
        for row in rows {
            cumulative += doubleValue(row.total)
            if selectedAngle <= cumulative {
                return row
            }
        }
        return rows.last
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let selectedRow {
                    SpendingSliceCallout(name: selectedRow.name, amountText: selectedRow.amountText)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .accessibilityHidden(true)

            Chart(rows) { row in
                let isSelected = selectedRow?.id == row.id
                let hasSelection = selectedRow != nil
                SectorMark(
                    angle: .value("Amount", doubleValue(row.total)),
                    outerRadius: .ratio(isSelected ? 1.0 : 0.92),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(Theme.chartColor(for: row.id, among: rowIDs))
                .opacity(hasSelection && !isSelected ? 0.45 : 1)
                .accessibilityLabel(row.name)
                .accessibilityValue(row.amountText)
            }
            .chartAngleSelection(value: $selectedAngle)
            .chartLegend(.hidden)
            .frame(height: 240)
            .sensoryFeedback(.selection, trigger: selectedRow?.id) { old, new in
                !reduceMotion && old != new && new != nil
            }
        }
        .accessibilityIdentifier("insights.chart")
        .accessibilityLabel("Spending breakdown pie chart. Press and drag around the chart to inspect category amounts.")
        .accessibilityValue(selectionAccessibilityValue)
    }

    private var selectionAccessibilityValue: String {
        guard let selectedRow else {
            return "No category selected"
        }
        return "\(selectedRow.name), \(selectedRow.amountText)"
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

/// Callout shown while scrubbing a pie sector (name + dollar amount).
struct SpendingSliceCallout: View {
    let name: String
    let amountText: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var usesSolidBackground: Bool {
        reduceTransparency || contrast == .increased
    }

    private var backgroundColor: Color {
        if usesSolidBackground {
            return Color(uiColor: .secondarySystemGroupedBackground)
        }
        return Color(uiColor: colorScheme == .dark
            ? UIColor(white: 0.18, alpha: 0.94)
            : UIColor(white: 1.0, alpha: 0.96))
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(amountText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(uiColor: .label))
            Text(name)
                .font(.caption2)
                .foregroundStyle(Color(uiColor: contrast == .increased ? .label : .secondaryLabel))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: contrast == .increased ? 1.5 : 1)
        )
        .compositingGroup()
        .colorScheme(colorScheme)
    }
}
