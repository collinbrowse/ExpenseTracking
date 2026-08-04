import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section("Security") {
                Toggle(viewModel.appLock.requireLockToggleTitle, isOn: viewModel.requireLockBinding)
                    .disabled(!viewModel.appLock.canAuthenticate && !viewModel.appLock.isEnabled)

                if !viewModel.appLock.canAuthenticate && !viewModel.appLock.isEnabled {
                    Text("Set a device passcode to enable app lock.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("When enabled, Cash Flow locks after 15 seconds in the background. Unlock with \(viewModel.appLock.biometryDisplayName) or your device passcode.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = viewModel.appLock.settingsErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Categorization") {
                NavigationLink {
                    CategorizationRulesView(
                        viewModel: CategorizationRulesViewModel(
                            ruleRepository: viewModel.ruleRepository,
                            ruleApplying: viewModel.ruleApplying,
                            accountRepository: viewModel.accountRepository
                        )
                    )
                } label: {
                    Text("Categorization Rules")
                }
            }

            Section("About") {
                LabeledContent("Version", value: viewModel.appVersion)
                LabeledContent("Build", value: viewModel.appBuild)
            }
            Section("Data") {
                Text("Transaction data is stored on this device. Deleting the app removes local data; reconnect to sync again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
