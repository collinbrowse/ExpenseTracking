import SwiftUI

/// Compact capsule chip for tag pickers and add affordances.
struct TagChip: View {
    enum Kind: Equatable {
        case selectable(selected: Bool)
        case add
        case plain
        /// Quieter chip for transaction list rows.
        case row
    }

    let title: String
    var kind: Kind = .plain

    var body: some View {
        HStack(spacing: kind == .row ? 0 : 4) {
            if case .add = kind {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
            }
            Text(title)
                .lineLimit(1)
            if case .selectable(selected: true) = kind {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
            }
        }
        .font(font)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .overlay {
            if showsBorder {
                Capsule()
                    .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1, dash: kindIsAdd ? [4, 3] : []))
            }
        }
    }

    private var kindIsAdd: Bool {
        if case .add = kind { return true }
        return false
    }

    private var font: Font {
        switch kind {
        case .row:
            return .caption2.weight(.medium)
        case .selectable, .add, .plain:
            return .subheadline.weight(.medium)
        }
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .row: 7
        case .selectable, .add, .plain: 12
        }
    }

    private var verticalPadding: CGFloat {
        switch kind {
        case .row: 3
        case .selectable, .add, .plain: 7
        }
    }

    private var showsBorder: Bool {
        switch kind {
        case .selectable(selected: false), .add, .plain:
            return true
        case .selectable(selected: true), .row:
            return false
        }
    }

    private var foreground: Color {
        switch kind {
        case .selectable(selected: true):
            return .white
        case .selectable(selected: false), .plain:
            return .primary
        case .add:
            return .accentColor
        case .row:
            return Color(uiColor: .secondaryLabel)
        }
    }

    private var background: Color {
        switch kind {
        case .selectable(selected: true):
            return .accentColor
        case .selectable(selected: false), .plain, .add:
            return Color(uiColor: .secondarySystemFill)
        case .row:
            return Color(uiColor: .tertiarySystemFill)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .add:
            return Color.accentColor.opacity(0.55)
        default:
            return Color(uiColor: .separator)
        }
    }
}

/// Horizontal tag scroller with an optional trailing “+ Add” chip that expands to a field.
struct TagChipScroller<ID: Hashable>: View {
    struct Item: Identifiable {
        let id: ID
        let title: String
        let isSelected: Bool
        let accessibilityKey: String

        init(id: ID, title: String, isSelected: Bool, accessibilityKey: String? = nil) {
            self.id = id
            self.title = title
            self.isSelected = isSelected
            self.accessibilityKey = accessibilityKey ?? title
        }
    }

    let items: [Item]
    var showsAddChip: Bool = true
    var isComposing: Bool
    @Binding var draftName: String
    var onSelect: (ID) -> Void
    var onBeginCompose: () -> Void
    var onSubmitCompose: () -> Void
    var onCancelCompose: (() -> Void)? = nil
    var accessibilityPrefix: String = "tags"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        onSelect(item.id)
                    } label: {
                        TagChip(
                            title: item.title,
                            kind: .selectable(selected: item.isSelected)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(accessibilityPrefix).chip.\(item.accessibilityKey)")
                    .accessibilityAddTraits(item.isSelected ? .isSelected : [])
                }

                if isComposing {
                    HStack(spacing: 6) {
                        TextField("Tag name", text: $draftName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(onSubmitCompose)
                            .frame(minWidth: 96)
                            .accessibilityIdentifier("\(accessibilityPrefix).newName")

                        Button(action: onSubmitCompose) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Save tag")
                        .accessibilityIdentifier("\(accessibilityPrefix).add")

                        if let onCancelCompose {
                            Button(action: onCancelCompose) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cancel")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                } else if showsAddChip {
                    Button(action: onBeginCompose) {
                        TagChip(title: "Add", kind: .add)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(accessibilityPrefix).compose")
                }
            }
            .padding(.vertical, 2)
        }
    }
}
