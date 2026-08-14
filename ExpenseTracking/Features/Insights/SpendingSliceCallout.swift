import SwiftUI

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
