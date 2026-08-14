import SwiftUI
import CashFlowKit

struct ImportHistoryView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var pendingDelete: ImportBatch?

    var body: some View {
        List {
            if viewModel.importBatches.isEmpty {
                ContentUnavailableView(
                    "No imports yet",
                    systemImage: "clock",
                    description: Text("CSV imports you run from Settings → Data will show up here.")
                )
            } else {
                ForEach(viewModel.importBatches) { batch in
                    Section {
                        LabeledContent("File", value: batch.fileName)
                        LabeledContent("Account", value: batch.accountName)
                        LabeledContent("Imported", value: DateFormatting.medium(batch.importedAt))
                        LabeledContent("Inserted", value: "\(batch.insertedCount)")
                        LabeledContent("Skipped", value: "\(batch.skippedCount)")
                        LabeledContent("Replaced", value: "\(batch.replacedCount)")
                        if batch.keepBothCount > 0 {
                            LabeledContent("Kept both", value: "\(batch.keepBothCount)")
                        }
                        LabeledContent("Status", value: batch.status == .active ? "Active" : "Deleted")
                        if let deletedAt = batch.deletedAt {
                            LabeledContent("Deleted", value: DateFormatting.medium(deletedAt))
                        }

                        if batch.status == .active {
                            Button("Delete imported data…", role: .destructive) {
                                pendingDelete = batch
                            }
                            .accessibilityIdentifier("settings.importHistory.delete.\(batch.id.rawValue)")
                        }
                    } header: {
                        Text(batch.fileName)
                    }
                }
            }
        }
        .navigationTitle("Import History")
        .task { await viewModel.reloadImportBatches() }
        .confirmationDialog(
            "Delete this import?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete data", role: .destructive) {
                guard let batch = pendingDelete else { return }
                pendingDelete = nil
                Task { await viewModel.deleteImportBatch(batch.id) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Removes transactions from this import. If the account was created by the import and has no other transactions, it is removed too. The history entry stays as deleted.")
        }
        .alert(
            "Couldn't delete import",
            isPresented: Binding(
                get: { viewModel.importHistoryErrorMessage != nil },
                set: { if !$0 { viewModel.importHistoryErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.importHistoryErrorMessage = nil }
        } message: {
            Text(viewModel.importHistoryErrorMessage ?? "")
        }
    }
}
