import SwiftUI
import CashFlowKit

struct ImportCSVAccountContent: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section("Import into") {
                Picker("Account", selection: $viewModel.importAccountMode) {
                    Text("Existing account").tag(ImportAccountMode.existing)
                    Text("New account").tag(ImportAccountMode.createNew)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.import.accountMode")

                if viewModel.importAccountMode == .existing {
                    Picker("Account", selection: $viewModel.importSelectedAccountID) {
                        Text("Select…").tag(Optional<AccountID>.none)
                        ForEach(viewModel.importAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                } else {
                    TextField("Account name", text: $viewModel.importNewAccountName)
                        .accessibilityIdentifier("settings.import.newAccountName")
                    TextField("Institution (optional)", text: $viewModel.importNewInstitutionName)
                }
            }

            Section {
                Button("Continue") {
                    Task { await viewModel.prepareImportConflicts() }
                }
                .disabled(!viewModel.canContinueImportAccountStep)
                .accessibilityIdentifier("settings.import.account.continue")
            }
        }
    }
}
