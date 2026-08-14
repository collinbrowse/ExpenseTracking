import SwiftUI
import CashFlowKit

struct TransactionRowView: View {
    let row: TransactionRowModel

    private var amountColor: Color {
        if row.isPending {
            return Theme.muted
        }
        return row.amountIsIncome ? Theme.positive : Color.primary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: CategoryIcon.systemName(for: row.categoryID))
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(row.categoryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !row.tagChipLabels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(row.tagChipLabels, id: \.self) { label in
                            TagChip(title: label, kind: .row)
                        }
                    }
                    .padding(.top, 1)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Tags \(row.tagChipLabels.joined(separator: ", "))")
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(row.amountText)
                    .font(.body.weight(row.isPending ? .medium : .semibold).monospacedDigit())
                    .foregroundStyle(amountColor)
                Text(row.dateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
