import SwiftUI
import CashFlowKit

struct SettingsView: View {
    let ruleRepository: any CategorizationRuleRepository
    let ruleApplying: any CategorizationRuleApplying
    let accountRepository: any AccountRepository

    var body: some View {
        List {
            Section("Categorization") {
                NavigationLink {
                    CategorizationRulesView(
                        viewModel: CategorizationRulesViewModel(
                            ruleRepository: ruleRepository,
                            ruleApplying: ruleApplying,
                            accountRepository: accountRepository
                        )
                    )
                } label: {
                    Text("Categorization Rules")
                }
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: appBuild)
            }
            Section("Data") {
                Text("Transaction data is stored on this device. Deleting the app removes local data; reconnect to sync again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
