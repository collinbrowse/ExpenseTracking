import SwiftUI

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
