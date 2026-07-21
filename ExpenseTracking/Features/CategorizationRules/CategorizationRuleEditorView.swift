import SwiftUI
import CashFlowKit

struct CategorizationRuleEditorView: View {
    @Bindable var viewModel: CategorizationRuleEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: EditorFocus?

    private enum EditorFocus: Hashable {
        case condition(UUID)
        case rename
    }

    private let controlMinHeight: CGFloat = 44
    private let trailingIconSize: CGFloat = 28

    var body: some View {
        Form {
            Section {
                Picker("Rule type", selection: $viewModel.selectedTab) {
                    ForEach(RuleEditorTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .accessibilityLabel("Rule type")
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
                switch viewModel.selectedTab {
                case .categorize:
                    Picker("Category", selection: $viewModel.categoryID) {
                        ForEach(SystemCategory.allCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                case .rename:
                    valueTextField(
                        focus: .rename,
                        placeholder: "Tap to enter new title",
                        text: $viewModel.renameTitle,
                        keyboard: .default
                    )
                }
            } header: {
                Text("Then")
            } footer: {
                switch viewModel.selectedTab {
                case .categorize:
                    Text("Matching transactions are assigned this category.")
                case .rename:
                    Text("Matching transactions get this merchant title. Location is kept.")
                }
            }

            Section {
                Toggle("Enabled", isOn: $viewModel.isEnabled)
            }

            if viewModel.canDelete {
                Section {
                    Button("Delete Rule", role: .destructive) {
                        viewModel.showDeleteConfirmation = true
                    }
                    .disabled(viewModel.isSaving)
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
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .disabled(viewModel.isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
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
        .interactiveDismissDisabled(viewModel.isSaving)
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
        .task {
            await viewModel.onAppear()
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
        case .titleContains, .titleEquals, .descriptionContains, .descriptionEquals:
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
                    // While typing, only keep a `$` prefix so "50" isn't snapped to "$5.00".
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

    private func formatAllAmountConditions() {
        for condition in viewModel.conditions {
            viewModel.formatAmountCondition(id: condition.id)
        }
    }

    /// Keeps a leading `$` while the user types; full `$X.XX` formatting happens on blur/save.
    private static func ensureCurrencyPrefix(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed == "$" { return "$" }
        let stripped = trimmed.replacingOccurrences(of: "$", with: "")
        guard !stripped.isEmpty else { return "$" }
        return trimmed.hasPrefix("$") ? trimmed : "$\(stripped)"
    }
}
