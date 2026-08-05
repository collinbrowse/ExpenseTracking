import SwiftUI
import CashFlowKit

struct TransactionsView: View {
    @Bindable var viewModel: TransactionsViewModel
    var makeAssistantViewModel: (() -> AssistantViewModel)?
    @State private var editorDetent: PresentationDetent = .large
    @State private var isComposingTag = false
    /// `sheet(item:)` so the first present always has a ViewModel (Bool + optional races empty).
    @State private var presentedAssistant: PresentedAssistant?

    var body: some View {
        List {
            if let progress = viewModel.syncProgress {
                SyncProgressBanner(progress: progress)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if let banner = viewModel.bannerMessage {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }

            if viewModel.hasActiveFilters {
                activeFiltersRow
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            if viewModel.sections.isEmpty && !viewModel.isLoadingPage {
                ContentUnavailableView(
                    viewModel.searchText.isEmpty ? "No transactions" : "No results",
                    systemImage: "list.bullet.rectangle",
                    description: Text(
                        viewModel.searchText.isEmpty
                            ? "Try adjusting filters or syncing accounts."
                            : "Try a different search."
                    )
                )
                .accessibilityIdentifier("transactions.empty")
            } else {
                // Month titles are regular rows (not Section headers) so they scroll
                // away instead of pinning under the nav/search bar.
                ForEach(viewModel.sections) { section in
                    Text(section.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(section.rows) { row in
                        Button {
                            viewModel.openEditor(for: row.id)
                        } label: {
                            TransactionRowView(row: row)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .accessibilityIdentifier("transactions.row.\(row.id.rawValue)")
                        .accessibilityLabel(accessibilityLabel(for: row))
                        .onAppear {
                            Task {
                                await viewModel.loadNextPageIfNeeded(currentRowID: row.id)
                            }
                        }
                    }
                }

                if viewModel.isLoadingPage {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Transactions")
        .accessibilityIdentifier("transactions.list")
        .searchable(text: $viewModel.searchText, prompt: "Search")
        .toolbar {
            if makeAssistantViewModel != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let makeAssistantViewModel {
                            presentedAssistant = PresentedAssistant(
                                viewModel: makeAssistantViewModel()
                            )
                        }
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Assistant")
                    .accessibilityIdentifier("transactions.assistant")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showFilters = true
                } label: {
                    Image(
                        systemName: viewModel.hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease"
                    )
                }
                .accessibilityLabel(
                    viewModel.hasActiveFilters
                        ? "Filters, \(viewModel.activeFilterChips.count) active"
                        : "Filters"
                )
                .accessibilityIdentifier("transactions.filters")
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(isPresented: $viewModel.showFilters) {
            filtersSheet
        }
        .sheet(item: $presentedAssistant, onDismiss: {
            Task { await viewModel.resetAndLoad() }
        }) { presented in
            NavigationStack {
                AssistantView(viewModel: presented.viewModel)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.selectedTransactionID != nil },
            set: { if !$0 { viewModel.selectedTransactionID = nil } }
        )) {
            editorSheet
                .presentationDetents([.medium, .large], selection: $editorDetent)
                .onAppear { editorDetent = .large }
        }
    }

    private func accessibilityLabel(for row: TransactionRowModel) -> String {
        if row.isPending {
            return "\(row.title), \(row.categoryText), \(row.amountText), Pending"
        }
        return "\(row.title), \(row.categoryText), \(row.amountText), \(row.dateText)"
    }

    private var activeFiltersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.activeFilterChips) { chip in
                    HStack(spacing: 6) {
                        Button {
                            viewModel.showFilters = true
                        } label: {
                            Text(chipLabel(for: chip))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await viewModel.clearFilter(chip.kind) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear \(chipLabel(for: chip)) filter")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("transactions.filterChip.\(chip.kind.rawValue)")
                }

                if viewModel.activeFilterChips.count > 1 {
                    Button("Clear all") {
                        Task { await viewModel.clearAllFilters() }
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("transactions.filters.clearAll")
                }
            }
        }
        .accessibilityIdentifier("transactions.activeFilters")
    }

    private func chipLabel(for chip: ActiveFilterChip) -> String {
        switch chip.kind {
        case .account: "Account: \(chip.label)"
        case .date: "Date: \(chip.label)"
        case .category: "Category: \(chip.label)"
        case .tag: "Tag: \(chip.label)"
        }
    }

    private var filtersSheet: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Picker("Account", selection: $viewModel.filterAccountID) {
                        Text("All").tag(Optional<AccountID>.none)
                        ForEach(viewModel.accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    .accessibilityIdentifier("transactions.filter.account")
                }

                Section("Date") {
                    Picker("Date", selection: $viewModel.filterDateOption) {
                        ForEach(TransactionDateFilterOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .accessibilityIdentifier("transactions.filter.date")

                    if viewModel.filterDateOption == .custom {
                        DatePicker("Start", selection: $viewModel.customStart, displayedComponents: .date)
                        DatePicker("End", selection: $viewModel.customEnd, displayedComponents: .date)
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $viewModel.filterCategoryID) {
                        Text("All").tag(Optional<CategoryID>.none)
                        ForEach(SystemCategory.allCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    .accessibilityIdentifier("transactions.filter.category")
                }

                Section("Tag") {
                    Picker("Tag", selection: $viewModel.filterTagID) {
                        Text("All").tag(Optional<TagID>.none)
                        ForEach(viewModel.tags) { tag in
                            Text(tag.name).tag(Optional(tag.id))
                        }
                    }
                    .accessibilityIdentifier("transactions.filter.tag")
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showFilters = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task { await viewModel.applyFilters() }
                    }
                }
            }
        }
    }

    private var editorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Description", text: $viewModel.editingDescription)
                        Image(systemName: "pencil")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
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

                if let location = viewModel.editingLocation, !location.isEmpty {
                    Section {
                        Text(location)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("transactions.editor.location")
                            .accessibilityLabel("Location \(location)")
                    } header: {
                        Text("Location")
                    }
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

private struct TransactionRowView: View {
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

/// Identifiable wrapper so `sheet(item:)` always presents with a live ViewModel.
private struct PresentedAssistant: Identifiable {
    let id = UUID()
    let viewModel: AssistantViewModel
}
