import SwiftUI
import CashFlowKit

struct ImportCSVMappingContent: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            if let preset = viewModel.importPreview?.mapping.presetName {
                Section {
                    Text("Detected format: \(preset)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Columns") {
                if let preview = viewModel.importPreview {
                    ForEach(Array(preview.headers.enumerated()), id: \.offset) { index, header in
                        Picker(header.isEmpty ? "Column \(index + 1)" : header, selection: Binding(
                            get: { viewModel.importMapping.assignments[index] ?? .ignore },
                            set: { viewModel.setImportColumn($0, at: index) }
                        )) {
                            ForEach(CSVImportColumn.allCases, id: \.self) { column in
                                Text(columnLabel(column)).tag(column)
                            }
                        }
                    }
                }
            }

            Section("Sample") {
                if let preview = viewModel.importPreview {
                    Text("\(preview.validRowCount) valid · \(preview.invalidRowCount) invalid")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.import.rowCounts")
                }
            }

            Section {
                Button("Continue") {
                    Task {
                        await viewModel.reparseImportWithCurrentMapping()
                        if viewModel.importMapping.isReady {
                            viewModel.importStep = .account
                        }
                    }
                }
                .disabled(!(viewModel.importMapping.isReady))
                .accessibilityIdentifier("settings.import.mapping.continue")
            }
        }
    }

    private func columnLabel(_ column: CSVImportColumn) -> String {
        switch column {
        case .postedDate: return "Date"
        case .amount: return "Amount"
        case .debit: return "Debit"
        case .credit: return "Credit"
        case .description: return "Description"
        case .currency: return "Currency"
        case .category: return "Category"
        case .account: return "Account (ignored)"
        case .tags: return "Tags"
        case .pending: return "Pending"
        case .location: return "Location"
        case .title: return "Title"
        case .externalID: return "External ID"
        case .ignore: return "Ignore"
        }
    }
}
