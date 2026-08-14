import SwiftUI
import CashFlowKit

struct InsightsView: View {
    @Bindable var viewModel: InsightsViewModel
    var onViewTransactions: (_ categoryID: CategoryID?, _ tagID: TagID?) -> Void = { _, _ in }
    @State private var selectedCategoryRowID: String?
    @State private var selectedTagRowID: String?

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

                if viewModel.isLoading && !viewModel.hasExpenseData {
                    ProgressView("Loading spending…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                        .accessibilityIdentifier("insights.loading")
                } else {
                    spendingHeader

                    categorySection

                    tagSection

                    if viewModel.hasExpenseData {
                        Button {
                            let categoryID = selectedCategoryRowID.map { CategoryID($0) }
                            let tagID = selectedTagRowID.map { TagID($0) }
                            onViewTransactions(categoryID, tagID)
                        } label: {
                            Label("View transactions", systemImage: "list.bullet")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("insights.viewTransactions")
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
        .onChange(of: viewModel.categoryRows.map(\.id)) { _, ids in
            if let selectedCategoryRowID, !ids.contains(selectedCategoryRowID) {
                self.selectedCategoryRowID = nil
            }
        }
        .onChange(of: viewModel.tagRows.map(\.id)) { _, ids in
            if let selectedTagRowID, !ids.contains(selectedTagRowID) {
                self.selectedTagRowID = nil
            }
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
            ManageTagsSheet(viewModel: viewModel)
        }
    }

    private var spendingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total spent")
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
                Text("No expenses in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("insights.category.empty")
            } else {
                let chartRows = Array(viewModel.categoryRows.prefix(8))
                SpendingBreakdownChartView(
                    rows: chartRows,
                    selectedRowID: $selectedCategoryRowID
                )
                saleTagScroller(
                    rows: chartRows,
                    selectedRowID: $selectedCategoryRowID,
                    accessibilityPrefix: "insights.category"
                )
            }
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.tagSectionTitle)
                .font(.title3.weight(.semibold))

            if viewModel.tagRows.isEmpty {
                Text("Tag transactions to track trips, events, and projects.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("insights.tag.empty")
            } else {
                let chartRows = Array(viewModel.tagRows.prefix(8))
                SpendingBreakdownChartView(
                    rows: chartRows,
                    selectedRowID: $selectedTagRowID
                )
                saleTagScroller(
                    rows: chartRows,
                    selectedRowID: $selectedTagRowID,
                    accessibilityPrefix: "insights.tag"
                )
            }
        }
    }

    private func saleTagScroller(
        rows: [InsightsSliceRow],
        selectedRowID: Binding<String?>,
        accessibilityPrefix: String
    ) -> some View {
        let chartIDs = rows.map(\.id)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(rows) { row in
                    let isSelected = selectedRowID.wrappedValue == row.id
                    Button {
                        if selectedRowID.wrappedValue == row.id {
                            selectedRowID.wrappedValue = nil
                        } else {
                            selectedRowID.wrappedValue = row.id
                        }
                    } label: {
                        SaleTagChip(
                            title: row.name,
                            percentText: "\(Int((row.share * 100).rounded()))%",
                            color: Theme.chartColor(for: row.id, among: chartIDs),
                            isSelected: isSelected
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(accessibilityPrefix).\(row.id)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityLabel("\(row.name), \(Int((row.share * 100).rounded())) percent")
                    .accessibilityValue(isSelected ? "Selected, \(row.amountText)" : row.amountText)
                    .accessibilityHint("Pins this category on the chart. Tap again to clear.")
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("\(accessibilityPrefix).tags")
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
}
