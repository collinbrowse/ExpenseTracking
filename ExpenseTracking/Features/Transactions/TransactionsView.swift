import SwiftUI
import CashFlowKit

struct TransactionsView: View {
    @Bindable var viewModel: TransactionsViewModel

    var body: some View {
        List {
            if let banner = viewModel.bannerMessage {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showFilters = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filters")
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
        .sheet(isPresented: Binding(
            get: { viewModel.selectedTransactionID != nil },
            set: { if !$0 { viewModel.selectedTransactionID = nil } }
        )) {
            editorSheet
        }
    }

    private func accessibilityLabel(for row: TransactionRowModel) -> String {
        "\(row.title), \(row.categoryText), \(row.amountText), \(row.dateText)"
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
                } footer: {
                    // Footer sits outside the inset grouped card; system spacing
                    // matches the title → section gap above.
                    Text(viewModel.editingAccountName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("transactions.editor.account")
                        .accessibilityLabel("Account \(viewModel.editingAccountName)")
                }
            }
            .navigationTitle("Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.selectedTransactionID = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.saveEdits() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct TransactionRowView: View {
    let row: TransactionRowModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: CategoryIcon.systemName(for: row.categoryID))
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(row.categoryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(row.amountText)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(row.amountIsIncome ? Theme.positive : Color.primary)
                Text(row.dateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
