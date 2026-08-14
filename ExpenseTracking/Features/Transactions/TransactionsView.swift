import SwiftUI
import CashFlowKit

struct TransactionsView: View {
    @Bindable var viewModel: TransactionsViewModel
    var makeAssistantViewModel: (() -> AssistantViewModel)?
    @State private var editorDetent: PresentationDetent = .large
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
        .onChange(of: viewModel.filters.revision) { _, _ in
            Task { await viewModel.handleFilterRevisionChange() }
        }
        .sheet(isPresented: $viewModel.showFilters) {
            TransactionFiltersSheet(viewModel: viewModel)
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
            TransactionEditorSheet(viewModel: viewModel)
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
                            viewModel.clearFilter(chip.kind)
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
                        viewModel.clearAllFilters()
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
}

/// Identifiable wrapper so `sheet(item:)` always presents with a live ViewModel.
private struct PresentedAssistant: Identifiable {
    let id = UUID()
    let viewModel: AssistantViewModel
}
