import SwiftUI
import CashFlowKit

struct TransactionFiltersSheet: View {
    @Bindable var viewModel: TransactionsViewModel

    var body: some View {
        NavigationStack {
            Form {
                TransactionFiltersForm(
                    filters: viewModel.filters,
                    accounts: viewModel.accounts,
                    tags: viewModel.tags,
                    accessibilityPrefix: "transactions.filter"
                )
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showFilters = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.applyFilters()
                    }
                }
            }
        }
    }
}
