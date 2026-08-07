import SwiftUI
import Charts
import CashFlowKit

/// Interactive spending pie chart with press-and-drag angle selection.
/// Selection stays pinned after finger lift; dollar amounts show in the callout.
struct SpendingBreakdownChartView: View {
    let rows: [InsightsSliceRow]
    @Binding var selectedRowID: String?

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
            .chartLegend(.hidden)
            .frame(height: 240)
            .onChange(of: gestureAngle) { _, newValue in
                guard let newValue, let row = row(forAngle: newValue) else { return }
                // Pin on every live angle update so selection survives finger lift
                // (Charts clears gestureAngle when the gesture ends).
                if selectedRowID != row.id {
                    selectedRowID = row.id
                }
            }
            .sensoryFeedback(.selection, trigger: selectedRow?.id) { old, new in
                !reduceMotion && old != new && new != nil
            }
        }
        .accessibilityIdentifier("insights.chart")
        .accessibilityLabel("Spending breakdown pie chart. Tap or press and drag to inspect category amounts.")
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

/// Callout shown for the pinned / scrubbed pie sector (name + dollar amount).
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

/// Retail-style hang tag used as a compact category/tag legend chip.
struct SaleTagChip: View {
    let title: String
    let percentText: String
    let color: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(percentText)
                    .font(.caption2.weight(.medium).monospacedDigit())
            }
            .foregroundStyle(Theme.contrastingLabel(on: color))
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(color, in: SaleTagShape())
        .overlay(
            SaleTagShape()
                .strokeBorder(Color.primary.opacity(isSelected ? 0.45 : 0.12), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.22 : 0.08), radius: isSelected ? 4 : 2, y: 1)
        .opacity(isSelected ? 1 : 0.92)
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

/// Price-tag silhouette: pointed leading edge + rounded trailing corners.
struct SaleTagShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let tipWidth = min(r.height * 0.42, r.width * 0.28)
        let corner = min(8, r.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: r.minX + tipWidth, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - corner, y: r.minY))
        path.addQuadCurve(
            to: CGPoint(x: r.maxX, y: r.minY + corner),
            control: CGPoint(x: r.maxX, y: r.minY)
        )
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - corner))
        path.addQuadCurve(
            to: CGPoint(x: r.maxX - corner, y: r.maxY),
            control: CGPoint(x: r.maxX, y: r.maxY)
        )
        path.addLine(to: CGPoint(x: r.minX + tipWidth, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.midY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> SaleTagShape {
        SaleTagShape(insetAmount: insetAmount + amount)
    }
}
