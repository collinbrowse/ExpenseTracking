import SwiftUI
import UniformTypeIdentifiers
import CashFlowKit

@MainActor
enum ImportCSVStep: Int, Hashable {
    case pickFile
    case mapping
    case account
    case conflicts
    case confirming
}

struct ImportCSVSheet: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.importStep {
                case .pickFile:
                    ImportCSVPickFileContent { showFileImporter = true }
                case .mapping:
                    ImportCSVMappingContent(viewModel: viewModel)
                case .account:
                    ImportCSVAccountContent(viewModel: viewModel)
                case .conflicts:
                    ImportCSVConflictsContent(viewModel: viewModel)
                case .confirming:
                    ProgressView("Importing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.cancelImportFlow() }
                        .disabled(viewModel.isImporting)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                Task { await viewModel.handleImportFilePicked(result) }
            }
            .alert(
                "Import failed",
                isPresented: Binding(
                    get: { viewModel.importErrorMessage != nil },
                    set: { if !$0 { viewModel.importErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.importErrorMessage = nil }
            } message: {
                Text(viewModel.importErrorMessage ?? "")
            }
        }
    }

    private var title: String {
        switch viewModel.importStep {
        case .pickFile: return "Import CSV"
        case .mapping: return "Column Mapping"
        case .account: return "Account"
        case .conflicts: return "Duplicates"
        case .confirming: return "Importing"
        }
    }
}

enum ImportAccountMode: Hashable {
    case existing
    case createNew
}
