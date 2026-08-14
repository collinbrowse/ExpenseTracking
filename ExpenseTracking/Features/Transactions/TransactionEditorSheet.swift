import SwiftUI
import CashFlowKit

struct TransactionEditorSheet: View {
    @Bindable var viewModel: TransactionsViewModel
    @State private var isComposingTag = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Title", text: $viewModel.editingDescription)
                        Image(systemName: "pencil")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    Text(viewModel.editingAmountText)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(
                            viewModel.editingAmountIsIncome ? Theme.positive : Theme.negative
                        )
                        .accessibilityIdentifier("transactions.editor.amount")
                        .accessibilityLabel("Amount \(viewModel.editingAmountText)")

                    if let sourceLabel = viewModel.editingIngestSourceLabel {
                        Text(sourceLabel)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("transactions.editor.ingestSource")
                    }

                    if viewModel.editingRawDescription
                        != viewModel.editingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    {
                        Text(viewModel.editingRawDescription)
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("transactions.editor.rawDescription")
                            .accessibilityLabel("Bank description \(viewModel.editingRawDescription)")
                    }

                    TextField("Location", text: $viewModel.editingLocation)
                        .accessibilityIdentifier("transactions.editor.location")

                    Picker("Category", selection: $viewModel.editingCategoryID) {
                        ForEach(SystemCategory.allCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .accessibilityIdentifier("transactions.editor.category")

                    Toggle("Lock category", isOn: $viewModel.editingCategoryLocked)
                        .accessibilityIdentifier("transactions.editor.lock")
                } footer: {
                    Text("When locked, rules won’t change this transaction’s category. Rename rules can still update the title.")
                }

                Section("Tags") {
                    TagChipScroller(
                        items: viewModel.tags.map {
                            TagChipScroller.Item(
                                id: $0.id,
                                title: $0.name,
                                isSelected: viewModel.editingTagIDs.contains($0.id),
                                accessibilityKey: $0.id.rawValue
                            )
                        },
                        isComposing: isComposingTag,
                        draftName: $viewModel.newTagName,
                        onSelect: { viewModel.toggleEditingTag($0) },
                        onBeginCompose: { isComposingTag = true },
                        onSubmitCompose: {
                            Task {
                                await viewModel.createTagFromEditor()
                                if viewModel.newTagName
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                                {
                                    isComposingTag = false
                                }
                            }
                        },
                        onCancelCompose: {
                            isComposingTag = false
                            viewModel.newTagName = ""
                        },
                        accessibilityPrefix: "transactions.editor.tag"
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section {
                    Button("Create Rule…") {
                        viewModel.presentCreateRule()
                    }
                    .disabled(viewModel.isSavingEdits)
                    .accessibilityIdentifier("transactions.editor.createRule")
                }

                if !viewModel.matchingRules.isEmpty {
                    Section {
                        ForEach(viewModel.matchingRules) { rule in
                            Button {
                                viewModel.presentEditRule(rule)
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    Image(systemName: rule.appliesCategory
                                        ? CategoryIcon.systemName(for: rule.categoryID)
                                        : "pencil")
                                        .font(.body)
                                        .frame(width: 28, height: 28)
                                        .foregroundStyle(.primary)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(viewModel.ruleTitle(for: rule))
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            if let badge = viewModel.ruleAppliesBadge(for: rule) {
                                                Text(badge)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        Color(uiColor: .tertiarySystemFill),
                                                        in: Capsule()
                                                    )
                                            }
                                        }
                                        Text(viewModel.ruleSummary(for: rule))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer(minLength: 8)

                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit rule \(viewModel.ruleTitle(for: rule))")
                        }
                    } header: {
                        Text("Matching rules")
                    } footer: {
                        Text(
                            viewModel.editingCategoryLocked
                                ? "These rules match this transaction. Lock prevents category changes; rename can still apply."
                                : "Rules that match this transaction. Category and rename can each apply from different rules."
                        )
                    }
                }

                Section {
                    Text(viewModel.editingAccountName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("transactions.editor.account")
                        .accessibilityLabel("Account \(viewModel.editingAccountName)")
                } header: {
                    Text("Account")
                }
            }
            .navigationTitle("Edit Transaction")
            .dismissKeyboardOnEmptyTap()
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.editingDescription) { _, _ in
                viewModel.scheduleMatchingRulesRefresh()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.selectedTransactionID = nil
                        viewModel.matchingRules = []
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.saveEdits() }
                    }
                    .disabled(viewModel.isSavingEdits)
                }
            }
            .sheet(isPresented: $viewModel.showRuleEditor, onDismiss: {
                Task { await viewModel.handleRuleEditorDismissed() }
            }) {
                NavigationStack {
                    if let editor = viewModel.ruleEditor {
                        CategorizationRuleEditorView(viewModel: editor)
                    }
                }
            }
        }
    }
}
