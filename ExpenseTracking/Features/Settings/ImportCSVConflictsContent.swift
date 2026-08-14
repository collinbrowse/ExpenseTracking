import SwiftUI
import CashFlowKit

struct ImportCSVConflictsContent: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            if viewModel.importConflicts.isEmpty {
                Section {
                    Text("No duplicates found. Ready to import \(viewModel.importPreview?.validRowCount ?? 0) transactions.")
                        .foregroundStyle(.secondary)
                }

                importConfirmSection
            } else {
                Section {
                    Text("\(viewModel.importConflicts.count) duplicate\(viewModel.importConflicts.count == 1 ? "" : "s") matched by date, amount, description, and account. Choose an action for each, or apply one to all.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Skip all duplicates") {
                        viewModel.applyBulkConflictAction(.skip)
                    }
                    .accessibilityIdentifier("settings.import.conflicts.skipAll")
                    Button("Replace all duplicates") {
                        viewModel.applyBulkConflictAction(.replace)
                    }
                    .accessibilityIdentifier("settings.import.conflicts.replaceAll")
                    Button("Keep both for all") {
                        viewModel.applyBulkConflictAction(.keepBoth)
                    }
                    .accessibilityIdentifier("settings.import.conflicts.keepBothAll")
                }

                importConfirmSection

                Section("Conflicts") {
                    ForEach(viewModel.importConflicts) { conflict in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(conflict.importRow.description)
                                .font(.body)
                            Text(conflictSubtitle(conflict))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Action", selection: Binding(
                                get: { conflict.action },
                                set: { viewModel.setConflictAction($0, for: conflict.id) }
                            )) {
                                Text("Skip").tag(Optional.some(ImportConflictAction.skip))
                                Text("Replace").tag(Optional.some(ImportConflictAction.replace))
                                Text("Keep both").tag(Optional.some(ImportConflictAction.keepBoth))
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("settings.import.conflict.action.\(conflict.id)")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var importConfirmSection: some View {
        Section {
            Button("Import") {
                Task { await viewModel.commitImport() }
            }
            .disabled(!viewModel.canConfirmImport)
            .accessibilityIdentifier("settings.import.confirm")

            if !viewModel.importConflicts.isEmpty, !viewModel.importConflictsResolved {
                Text("Choose Skip, Replace, or Keep both for every duplicate before importing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let preview = viewModel.importPreview, preview.invalidRowCount > 0 {
                Text("Fix column mapping — \(preview.invalidRowCount) row(s) still invalid.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func conflictSubtitle(_ conflict: CSVImportConflict) -> String {
        let amount = CurrencyFormatting.usd(conflict.importRow.amount)
        let existing = CurrencyFormatting.usd(conflict.existingAmount)
        return "Import \(amount) → existing \(existing) · \(conflict.existingDescription)"
    }
}
