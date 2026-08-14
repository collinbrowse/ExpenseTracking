import SwiftUI
import Charts
import CashFlowKit

/// Interactive spending pie chart.
/// - Sale-tag chips pin a sticky selection (handled by the parent binding).
/// - On the pie itself, only press-and-drag scrubs sectors; taps do nothing.
/// - Drag highlight is live only — lifting the finger returns to the chip pin (or none).
struct SpendingBreakdownChartView: View {
    let rows: [InsightsSliceRow]
    @Binding var selectedRowID: String?

    /// Live scrub value while dragging; cleared on finger lift (never pinned from the pie).
    @State private var gestureAngle: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rowIDs: [String] {
        rows.map(\.id)
    }

    private var selectedRow: InsightsSliceRow? {
        if let gestureAngle, let fromGesture = row(forAngle: gestureAngle) {
            return fromGesture
        }
        guard let selectedRowID else { return nil }
        return rows.first { $0.id == selectedRowID }
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
            .chartAngleSelection(value: $gestureAngle)
            // Replace the default tap+drag selection with drag-only scrubbing.
            .chartGesture { proxy in
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let angle = proxy.angle(at: value.location)
                        proxy.selectAngleValue(at: angle)
                    }
                    .onEnded { _ in
                        gestureAngle = nil
                    }
            }
            .chartLegend(.hidden)
            .frame(height: 240)
            .sensoryFeedback(.selection, trigger: selectedRow?.id) { old, new in
                !reduceMotion && old != new && new != nil
            }
        }
        .accessibilityIdentifier("insights.chart")
        .accessibilityLabel("Spending breakdown pie chart. Press and drag to inspect amounts. Use category tags to pin a selection.")
        .accessibilityValue(selectionAccessibilityValue)
    }

    private var selectionAccessibilityValue: String {
        guard let selectedRow else {
            return "No category selected"
        }
        return "\(selectedRow.name), \(selectedRow.amountText)"
    }

    private func row(forAngle angle: Double) -> InsightsSliceRow? {
        var cumulative: Double = 0
        for row in rows {
            cumulative += doubleValue(row.total)
            if angle <= cumulative {
                return row
            }
        }
        return rows.last
    }

    private func doubleValue(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
