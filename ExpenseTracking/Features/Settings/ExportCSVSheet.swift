import SwiftUI
import CashFlowKit

struct ExportCSVSheet: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        @Bindable var filters = viewModel.filters
        NavigationStack {
            List {
                Section {
                    TextField("Search", text: $filters.searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("settings.export.search")
                } footer: {
                    Text(matchCountFooter)
                        .accessibilityIdentifier("settings.export.matchCount")
                }

                TransactionFiltersForm(
                    filters: filters,
                    accounts: viewModel.exportAccounts,
                    tags: viewModel.exportTags,
                    accessibilityPrefix: "settings.export.filter"
                )

                Section {
                    Button {
                        Task { await viewModel.exportLocalData() }
                    } label: {
                        if viewModel.isExporting {
                            HStack {
                                ProgressView()
                                Text("Exporting…")
                            }
                        } else {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(viewModel.isExporting)
                    .accessibilityIdentifier("settings.export.confirm")

                    if let message = viewModel.exportErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Export CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.showExportSheet = false }
                }
            }
            .task {
                viewModel.filters.enableSearchDebounce()
                await viewModel.refreshExportMatchCount()
            }
            .onChange(of: viewModel.filters.revision) { _, _ in
                Task { await viewModel.refreshExportMatchCount() }
            }
        }
    }

    private var matchCountFooter: String {
        guard let count = viewModel.exportMatchCount else {
            return "Counting matching transactions…"
        }
        return "\(count) transaction\(count == 1 ? "" : "s") will be exported"
    }
}
