import SwiftUI
import CashFlowKit

struct CategorizationRuleEditorView: View {
    @Bindable var viewModel: CategorizationRuleEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: EditorFocus?

    private enum EditorFocus: Hashable {
        case condition(UUID)
        case rename
        case renameLocation
        case naturalLanguage
    }

    private let controlMinHeight: CGFloat = 44
    private let trailingIconSize: CGFloat = 28

    var body: some View {
        Form {
            if viewModel.ruleDraftingAvailable {
                Section {
                    if viewModel.showNaturalLanguageEditor {
                        naturalLanguageEditor
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                    } else {
                        Button {
                            openNaturalLanguageEditor()
                        } label: {
                            Label("Edit with Natural Language", systemImage: "sparkles")
                        }
                        .accessibilityIdentifier("rules.editor.assistant.open")
                    }
                } footer: {
                    if viewModel.showNaturalLanguageEditor, let banner = viewModel.assistantBanner {
                        Text(banner)
                    } else if !viewModel.showNaturalLanguageEditor {
                        Text("Describe changes in plain language to fill the fields below. Review before saving.")
                    }
                }
            }

            Section {
                ForEach($viewModel.conditions) { $condition in
                    conditionEditor($condition)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let id = viewModel.conditions[index].id
                        viewModel.removeCondition(id: id)
                    }
                }

                Button {
                    viewModel.addCondition()
                } label: {
                    Label("Add condition", systemImage: "plus")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } header: {
                Text("If")
            } footer: {
                Text("All conditions must match. “Contains” matches whole words, even if other words sit between them.")
            }

            Section {
                Toggle("Set category", isOn: $viewModel.appliesCategory)
                if viewModel.appliesCategory {
                    Picker("Category", selection: $viewModel.categoryID) {
                        ForEach(SystemCategory.allCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                }
            } header: {
                Text("Then — Category")
            }

            Section {
                Toggle("Rename title / location", isOn: $viewModel.appliesRename)
                if viewModel.appliesRename {
                    valueTextField(
                        focus: .rename,
                        placeholder: "Tap to enter new title",
                        text: $viewModel.renameTitle,
                        keyboard: .default
                    )
                    valueTextField(
                        focus: .renameLocation,
                        placeholder: "Tap to enter location (optional)",
                        text: $viewModel.renameLocation,
                        keyboard: .default
                    )
                }
            } header: {
                Text("Then — Rename")
            } footer: {
                Text("Matching transactions get this merchant title and/or location. The raw bank description is never changed.")
            }

            Section {
                if viewModel.tags.isEmpty {
                    Text("No tags yet. Create tags from Insights or Transactions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.tags) { tag in
                        Button {
                            viewModel.toggleTag(tag.id)
                        } label: {
                            HStack {
                                Text(tag.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.selectedTagIDs.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .accessibilityLabel("Tag \(tag.name)")
                        .accessibilityAddTraits(
                            viewModel.selectedTagIDs.contains(tag.id) ? .isSelected : []
                        )
                    }
                }
            } header: {
                Text("Then — Add tags")
            } footer: {
                Text("Tags are additive. Removing a tag later on a transaction stops rules from re-adding it.")
            }

            Section {
                Toggle("Enabled", isOn: $viewModel.isEnabled)
            }

            if viewModel.canUndoApply {
                Section {
                    Button("Undo Rule…") {
                        viewModel.showUndoConfirmation = true
                    }
                    .disabled(!viewModel.canUndo)
                    .accessibilityIdentifier("rules.editor.undo")
                } footer: {
                    Text("Turns the rule off and reverts changes it made. Categories, tags, or titles you’ve edited since are kept.")
                }
            }

            if viewModel.canDelete {
                Section {
                    Button("Delete Rule", role: .destructive) {
                        viewModel.showDeleteConfirmation = true
                    }
                    .disabled(viewModel.isSaving || viewModel.isUndoing)
                    .accessibilityIdentifier("rules.editor.delete")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let banner = viewModel.assistantBanner, !viewModel.showNaturalLanguageEditor {
                Section {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(viewModel.navigationTitle)
                        .font(.headline)
                    if viewModel.showsAssistantBadge {
                        Label("Created by Assistant", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .labelStyle(.titleAndIcon)
                            .accessibilityLabel("Created by Assistant")
                    }
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(viewModel.isSaving || viewModel.isUndoing)
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving || viewModel.isUndoing {
                    ProgressView()
                } else {
                    Button("Save") {
                        formatAllAmountConditions()
                        Task {
                            await viewModel.save()
                            if viewModel.didSave {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSaving || viewModel.isUndoing)
        .dismissKeyboardOnEmptyTap()
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: focusedField) { previous, current in
            if case .condition(let id)? = previous,
               current != previous
            {
                viewModel.formatAmountCondition(id: id)
            }
        }
        .confirmationDialog(
            "Delete this rule?",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) {
                Task {
                    await viewModel.delete()
                    if viewModel.didSave {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Matching transactions will be re-evaluated without this rule.")
        }
        .confirmationDialog(
            "Undo this rule?",
            isPresented: $viewModel.showUndoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Undo Rule", role: .destructive) {
                Task {
                    await viewModel.undoApply()
                    if viewModel.didSave {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turns the rule off and reverts categories, tags, and renames it applied. Changes you’ve made since are kept.")
        }
        .task {
            await viewModel.onAppear()
        }
        .onChange(of: viewModel.showNaturalLanguageEditor) { _, isShown in
            if isShown {
                Task { @MainActor in
                    await Task.yield()
                    focusedField = .naturalLanguage
                }
            } else if focusedField == .naturalLanguage {
                focusedField = nil
            }
        }
    }

    private func openNaturalLanguageEditor() {
        viewModel.showNaturalLanguageEditor = true
        Task { @MainActor in
            await Task.yield()
            focusedField = .naturalLanguage
        }
    }

    private func closeNaturalLanguageEditor() {
        focusedField = nil
        viewModel.showNaturalLanguageEditor = false
    }

    @ViewBuilder
    private var naturalLanguageEditor: some View {
        if viewModel.canUseAssistant {
            // Outer padding keeps the floating close control inside the list-row clip bounds
            // while still sitting on the corner of the Form-colored field.
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .center, spacing: 10) {
                    TextField(
                        "Describe the rule…",
                        text: $viewModel.assistantPrompt,
                        axis: .vertical
                    )
                    .font(.body)
                    .lineLimit(1...3)
                    .focused($focusedField, equals: .naturalLanguage)
                    .accessibilityIdentifier("rules.editor.assistant.draft")

                    Button {
                        focusedField = nil
                        Task { await viewModel.draftFromNaturalLanguage() }
                    } label: {
                        Group {
                            if viewModel.isDrafting {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(canDraftFromNaturalLanguage ? Color.accentColor : Color.secondary)
                            }
                        }
                        .frame(width: 28, height: 28)
                    }
                    .disabled(!canDraftFromNaturalLanguage)
                    .accessibilityLabel("Draft rule with natural language")
                    .accessibilityIdentifier("rules.editor.assistant.send")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .padding(.top, 10)
                .padding(.trailing, 10)

                Button(action: closeNaturalLanguageEditor) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Color(uiColor: .tertiarySystemFill),
                            in: Circle()
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide natural language editor")
                .accessibilityIdentifier("rules.editor.assistant.close")
            }
        } else {
            Text(assistantUnavailableMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var canDraftFromNaturalLanguage: Bool {
        !viewModel.isDrafting
            && !viewModel.assistantPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var assistantUnavailableMessage: String {
        switch viewModel.assistantAvailability {
        case .available:
            return "Assistant is ready."
        case .deviceNotEligible:
            return "This device doesn’t support Apple Intelligence."
        case .appleIntelligenceOff:
            return "Turn on Apple Intelligence in Settings to draft rules with the assistant."
        case .modelNotReady:
            return "Apple Intelligence is still preparing. Try again shortly."
        case .unavailable:
            return "On-device intelligence isn’t available right now."
        }
    }

    @ViewBuilder
    private func conditionEditor(_ condition: Binding<EditableCondition>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            kindMenu(condition)
            valueControl(condition)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func kindMenu(_ condition: Binding<EditableCondition>) -> some View {
        Menu {
            ForEach(EditableCondition.Kind.allCases) { kind in
                Button(kind.label) {
                    condition.wrappedValue.kind = kind
                    if kind == .amountMin || kind == .amountMax {
                        condition.wrappedValue.formatAmountAsCurrency()
                    }
                    if kind == .categoryIs, condition.wrappedValue.categoryID == nil {
                        condition.wrappedValue.categoryID = SystemCategory.other.id
                    }
                    if kind == .hasTag,
                       condition.wrappedValue.tagID == nil,
                       let first = viewModel.tags.first
                    {
                        condition.wrappedValue.tagID = first.id
                    }
                    if kind == .account,
                       condition.wrappedValue.accountID == nil,
                       let first = viewModel.accounts.first
                    {
                        condition.wrappedValue.accountID = first.id
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(condition.wrappedValue.kind.label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: trailingIconSize, height: trailingIconSize)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: controlMinHeight, alignment: .leading)
            .background(
                Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .accessibilityLabel("Condition type, \(condition.wrappedValue.kind.label)")
    }

    @ViewBuilder
    private func valueControl(_ condition: Binding<EditableCondition>) -> some View {
        switch condition.wrappedValue.kind {
        case .titleContains, .titleEquals, .descriptionContains, .descriptionEquals, .locationContains:
            valueTextField(
                focus: .condition(condition.wrappedValue.id),
                placeholder: "Tap to enter text",
                text: condition.textValue,
                keyboard: .default
            )
        case .account:
            Menu {
                ForEach(viewModel.accounts) { account in
                    Button(account.name) {
                        condition.wrappedValue.accountID = account.id
                    }
                }
            } label: {
                valueChip(
                    text: accountLabel(for: condition.wrappedValue.accountID),
                    isPlaceholder: condition.wrappedValue.accountID == nil
                )
            }
            .accessibilityLabel("Account")
        case .categoryIs:
            Menu {
                ForEach(SystemCategory.allCategories) { category in
                    Button(category.name) {
                        condition.wrappedValue.categoryID = category.id
                    }
                }
            } label: {
                valueChip(
                    text: categoryLabel(for: condition.wrappedValue.categoryID),
                    isPlaceholder: condition.wrappedValue.categoryID == nil
                )
            }
            .accessibilityLabel("Category")
        case .hasTag:
            Menu {
                ForEach(viewModel.tags) { tag in
                    Button(tag.name) {
                        condition.wrappedValue.tagID = tag.id
                    }
                }
            } label: {
                valueChip(
                    text: tagLabel(for: condition.wrappedValue.tagID),
                    isPlaceholder: condition.wrappedValue.tagID == nil
                )
            }
            .accessibilityLabel("Tag")
        case .amountMin, .amountMax:
            amountTextField(condition)
        }
    }

    private func amountTextField(_ condition: Binding<EditableCondition>) -> some View {
        HStack(spacing: 8) {
            TextField("Tap to enter amount", text: condition.amountText)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .condition(condition.wrappedValue.id))
                .onChange(of: condition.wrappedValue.amountText) { _, newValue in
                    let prefixed = Self.ensureCurrencyPrefix(newValue)
                    if prefixed != newValue {
                        condition.wrappedValue.amountText = prefixed
                    }
                }

            Button {
                focusedField = .condition(condition.wrappedValue.id)
            } label: {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: trailingIconSize, height: trailingIconSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit amount")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: controlMinHeight, alignment: .leading)
        .background(
            Color(uiColor: .tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Amount")
    }

    private func valueTextField(
        focus: EditorFocus,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .focused($focusedField, equals: focus)

            Button {
                focusedField = focus
            } label: {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: trailingIconSize, height: trailingIconSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit value")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: controlMinHeight, alignment: .leading)
        .background(
            Color(uiColor: .tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }

    private func valueChip(text: String, isPlaceholder: Bool) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.body)
                .foregroundStyle(isPlaceholder ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: trailingIconSize, height: trailingIconSize)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: controlMinHeight, alignment: .leading)
        .background(
            Color(uiColor: .tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private func accountLabel(for id: AccountID?) -> String {
        guard let id else { return "Tap to choose account" }
        return viewModel.accounts.first(where: { $0.id == id })?.name ?? "Tap to choose account"
    }

    private func categoryLabel(for id: CategoryID?) -> String {
        guard let id else { return "Tap to choose category" }
        return SystemCategory.category(for: id).name
    }

    private func tagLabel(for id: TagID?) -> String {
        guard let id else { return "Tap to choose tag" }
        return viewModel.tags.first(where: { $0.id == id })?.name ?? "Tap to choose tag"
    }

    private func formatAllAmountConditions() {
        for condition in viewModel.conditions {
            viewModel.formatAmountCondition(id: condition.id)
        }
    }

    private static func ensureCurrencyPrefix(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed == "$" { return "$" }
        let stripped = trimmed.replacingOccurrences(of: "$", with: "")
        guard !stripped.isEmpty else { return "$" }
        return trimmed.hasPrefix("$") ? trimmed : "$\(stripped)"
    }
}
