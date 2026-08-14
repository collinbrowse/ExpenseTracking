import SwiftUI
import CashFlowKit

struct AccountRenameSheet: View {
    @Bindable var viewModel: AccountsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Account name", text: $viewModel.renamingName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("accounts.rename.field")
                } footer: {
                    Text("This name stays on this device. Sync won’t overwrite it for this account.")
                }
            }
            .navigationTitle("Rename Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancelRename() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.saveRename() }
                    }
                    .disabled(viewModel.renamingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("accounts.rename.save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
