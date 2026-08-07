import SwiftUI
import UIKit
import CashFlowKit

enum Theme {
    /// Accessible green for income / positive net (tuned for light & dark).
    static let positive = Color(uiColor: UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            // System-like green that stays readable on dark surfaces.
            UIColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1)
        default:
            // Deeper green for contrast on light / material surfaces.
            UIColor(red: 0.10, green: 0.48, blue: 0.24, alpha: 1)
        }
    })

    /// Outflow / negative net — high-contrast label color (Wallet-like), not red-by-default.
    static let negative = Color(uiColor: .label)

    static let muted = Color(uiColor: .secondaryLabel)
    /// Sync / connection problems on Accounts (high visibility, not destructive red).
    static let warning = Color(uiColor: .systemOrange)
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24

    /// Amount color for a signed cash-flow value.
    static func amountColor(for value: Decimal) -> Color {
        if value > 0 { return positive }
        if value < 0 { return negative }
        return Color(uiColor: .label)
    }
}

struct ChartSelectionCallout: View {
    let net: Decimal
    let date: Date

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var usesSolidBackground: Bool {
        reduceTransparency || contrast == .increased
    }

    private var amountColor: Color {
        // Prefer semantic positive green; for negative/zero use pure label so chart
        // tint / material cannot wash the text out.
        if net > 0 {
            return contrast == .increased
                ? Color(uiColor: .label) // max contrast when Increase Contrast is on
                : Theme.positive
        }
        return Color(uiColor: .label)
    }

    private var dateColor: Color {
        Color(uiColor: contrast == .increased ? .label : .secondaryLabel)
    }

    private var backgroundColor: Color {
        if usesSolidBackground {
            return Color(uiColor: .secondarySystemGroupedBackground)
        }
        // Near-opaque surface so the green chart fill cannot tint the labels.
        return Color(uiColor: colorScheme == .dark
            ? UIColor(white: 0.18, alpha: 0.94)
            : UIColor(white: 1.0, alpha: 0.96))
    }

    private var borderColor: Color {
        Color(uiColor: .separator)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(CurrencyFormatting.signedUSD(net))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(amountColor)
            Text(date, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(dateColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderColor, lineWidth: contrast == .increased ? 1.5 : 1)
        )
        // Break inheritance from Chart mark foreground styles (common tint bug).
        .compositingGroup()
        .colorScheme(colorScheme)
    }
}

enum CurrencyFormatting {
    static func usd(_ amount: Decimal) -> String {
        CashFlowCurrencyFormatting.usd(amount)
    }

    static func signedUSD(_ amount: Decimal) -> String {
        CashFlowCurrencyFormatting.signedUSD(amount)
    }
}

enum DateFormatting {
    private static let medium: Date.FormatStyle = .dateTime.month(.abbreviated).day().year()
    private static let list: Date.FormatStyle = .dateTime.month(.abbreviated).day().year()

    static func medium(_ date: Date) -> String {
        date.formatted(medium)
    }

    /// e.g. "Jul 15, 2026" — matches common bank list styling.
    static func list(_ date: Date) -> String {
        date.formatted(list)
    }
}
