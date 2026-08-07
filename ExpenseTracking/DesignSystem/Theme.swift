import SwiftUI
import UIKit

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

    /// Chart stroke/fill for values below zero (adaptive red; not used for Wallet-like amount text).
    static let chartNegative = Color(uiColor: UIColor { traits in
        switch traits.userInterfaceStyle {
        case .dark:
            UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1)
        default:
            UIColor(red: 0.80, green: 0.16, blue: 0.16, alpha: 1)
        }
    })

    static let muted = Color(uiColor: .secondaryLabel)
    /// Sync / connection problems on Accounts (high visibility, not destructive red).
    static let warning = Color(uiColor: .systemOrange)
    static let screenPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 24

    /// Distinct hues for Insights pie sectors / legend swatches (top 8 slices).
    static let chartPalette: [Color] = [
        Color(uiColor: .systemBlue),
        Color(uiColor: .systemOrange),
        Color(uiColor: .systemTeal),
        Color(uiColor: .systemPurple),
        Color(uiColor: .systemPink),
        Color(uiColor: .systemIndigo),
        Color(uiColor: .systemYellow),
        Color(uiColor: .systemBrown),
        Color(uiColor: .systemMint),
        Color(uiColor: .systemCyan)
    ]

    /// Amount color for a signed cash-flow value.
    static func amountColor(for value: Decimal) -> Color {
        if value > 0 { return positive }
        if value < 0 { return negative }
        return Color(uiColor: .label)
    }

    /// Stable pie/legend color for a slice id within the currently displayed rows.
    static func chartColor(for id: String, among ids: [String]) -> Color {
        guard !chartPalette.isEmpty else { return Color.accentColor }
        if let index = ids.firstIndex(of: id) {
            return chartPalette[index % chartPalette.count]
        }
        return chartPalette[stableIndex(for: id) % chartPalette.count]
    }

    private static func stableIndex(for id: String) -> Int {
        // Simple stable string hash (djb2) so colors do not jump across launches.
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(chartPalette.count))
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
        if contrast == .increased {
            return Color(uiColor: .label)
        }
        if net > 0 { return Theme.positive }
        if net < 0 { return Theme.chartNegative }
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
        amount.formatted(.currency(code: "USD"))
    }

    static func signedUSD(_ amount: Decimal) -> String {
        let formatted = usd(abs(amount))
        if amount > 0 { return "+\(formatted)" }
        if amount < 0 { return "−\(formatted)" }
        return formatted
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
