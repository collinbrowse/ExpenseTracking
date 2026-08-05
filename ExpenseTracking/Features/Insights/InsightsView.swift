import SwiftUI
import CashFlowKit

struct InsightsView: View {
    @Bindable var viewModel: InsightsViewModel
    /// Opens Transactions with the current Insights date range plus optional category/tag scope.
    var onViewTransactions: (CategoryID?, TagID?, TransactionDateFilterOption, Date, Date) -> Void
    @State private var isComposingTag = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                if let progress = viewModel.syncProgress {
                    SyncProgressBanner(progress: progress)
                }

                if let banner = viewModel.bannerMessage {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("insights.banner")
                }

                Picker("Range", selection: Binding(
                    get: { viewModel.selectedOption },
                    set: { viewModel.selectOption($0) }
                )) {
                    ForEach(viewModel.availableRangeOptions) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("insights.rangePicker")
                .disabled(viewModel.isLoading)

                if viewModel.isLoading && !viewModel.hasExpenseData && !viewModel.hasFocusFilters {
                    ProgressView("Loading spending…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                        .accessibilityIdentifier("insights.loading")
                } else {
                    if viewModel.hasFocusFilters {
                        focusFiltersRow
                    }

                    spendingHeader

                    categorySection

                    tagSection

                    if viewModel.hasFocusFilters {
                        viewTransactionsButton
                    }

                    manageTagsButton
                }
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle("Insights")
        .accessibilityIdentifier("insights.root")
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.onAppear()
        }
        .sheet(isPresented: $viewModel.showCustomRange) {
            NavigationStack {
                Form {
                    DatePicker("Start", selection: $viewModel.customStart, displayedComponents: .date)
                    DatePicker("End", selection: $viewModel.customEnd, displayedComponents: .date)
                }
                .navigationTitle("Custom Range")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { viewModel.showCustomRange = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            viewModel.applyCustomRange()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $viewModel.showManageTags) {
            manageTagsSheet
        }
    }

    private var focusFiltersRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Showing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let name = viewModel.focusCategoryName {
                        focusChip(label: name, kind: "category") {
                            viewModel.clearCategoryFocus()
                        }
                    }
                    if let name = viewModel.focusTagName {
                        focusChip(label: name, kind: "tag") {
                            viewModel.clearTagFocus()
                        }
                    }
                    if viewModel.focusCategoryID != nil && viewModel.focusTagID != nil {
                        Button("Clear all") {
                            viewModel.clearAllFocus()
                        }
                        .font(.subheadline)
                    }
                }
            }
            Text("Tap another category or tag to combine filters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("insights.focusFilters")
    }

    private func focusChip(label: String, kind: String, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear \(label)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
        .accessibilityIdentifier("insights.focus.\(kind)")
    }

    private var spendingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.hasFocusFilters ? "Filtered spend" : "Total spent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(viewModel.expenseTotalText)
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .accessibilityIdentifier("insights.expenseTotal")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.categorySectionTitle)
                .font(.title3.weight(.semibold))

            if viewModel.categoryRows.isEmpty {
                Text(
                    viewModel.hasFocusFilters
                        ? "No expenses match these filters."
                        : "No expenses in this range."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("insights.category.empty")
            } else {
                SpendingBreakdownChartView(rows: Array(viewModel.categoryRows.prefix(8)))
                ForEach(viewModel.categoryRows) { row in
                    let categoryID = CategoryID(row.id)
                    let selected = viewModel.focusCategoryID == categoryID
                    Button {
                        viewModel.toggleCategoryFocus(categoryID)
                    } label: {
                        sliceRow(row, isSelected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("insights.category.\(row.id)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.tagSectionTitle)
                .font(.title3.weight(.semibold))

            if viewModel.tagRows.isEmpty {
                Text(
                    viewModel.focusCategoryID != nil
                        ? "No tagged expenses in this category."
                        : "Tag transactions to track trips, events, and projects."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("insights.tag.empty")
            } else {
                SpendingBreakdownChartView(rows: Array(viewModel.tagRows.prefix(8)))
                ForEach(viewModel.tagRows) { row in
                    let tagID = TagID(row.id)
                    let selected = viewModel.focusTagID == tagID
                    Button {
                        viewModel.toggleTagFocus(tagID)
                    } label: {
                        sliceRow(row, isSelected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("insights.tag.\(row.id)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func sliceRow(_ row: InsightsSliceRow, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(isSelected ? "Filtered" : "\(Int((row.share * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            Spacer()
            Text(row.amountText)
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .tertiaryLabel))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
    }

    private var viewTransactionsButton: some View {
        Button {
            onViewTransactions(
                viewModel.focusCategoryID,
                viewModel.focusTagID,
                viewModel.drillDownDateOption,
                viewModel.customStart,
                viewModel.customEnd
            )
        } label: {
            Label("View transactions", systemImage: "list.bullet")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("insights.viewTransactions")
    }

    private var manageTagsButton: some View {
        Button {
            viewModel.prepareManageTags()
            viewModel.showManageTags = true
        } label: {
            Label("Manage Tags", systemImage: "tag")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("insights.manageTags")
    }

    private var manageTagsSheet: some View {
        NavigationStack {
            Form {
                if let error = viewModel.tagEditorError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("insights.tags.error")
                    }
                }

                Section {
                    TagChipScroller(
                        items: viewModel.tags.map {
                            TagChipScroller.Item(
                                id: $0.id,
                                title: $0.name,
                                isSelected: viewModel.renamingTagID == $0.id,
                                accessibilityKey: $0.id.rawValue
                            )
                        },
                        isComposing: isComposingTag,
                        draftName: $viewModel.newTagName,
                        onSelect: { id in
                            if let tag = viewModel.tags.first(where: { $0.id == id }) {
                                viewModel.beginRename(tag)
                            }
                        },
                        onBeginCompose: { isComposingTag = true },
                        onSubmitCompose: {
                            Task {
                                await viewModel.createTag()
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
                        accessibilityPrefix: "insights.tags"
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

                    if let renamingID = viewModel.renamingTagID {
                        HStack {
                            TextField("Rename tag", text: $viewModel.renameDraft)
                                .submitLabel(.done)
                                .onSubmit {
                                    Task { await viewModel.commitRename() }
                                }
                            Button("Save") {
                                Task { await viewModel.commitRename() }
                            }
                            .disabled(viewModel.isSavingTag)
                            Button("Delete", role: .destructive) {
                                if let tag = viewModel.tags.first(where: { $0.id == renamingID }) {
                                    Task { await viewModel.deleteTag(tag) }
                                }
                            }
                            .disabled(viewModel.isSavingTag)
                        }
                    }
                } footer: {
                    Text(
                        viewModel.renamingTagID == nil
                            ? "Tap a tag to rename or delete. Tags stay on this device."
                            : "Edit the name, then Save — or Delete to remove the tag."
                    )
                }
            }
            .navigationTitle("Tags")
            .dismissKeyboardOnEmptyTap()
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isComposingTag = false
                        viewModel.showManageTags = false
                    }
                }
            }
            .onAppear {
                isComposingTag = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}
