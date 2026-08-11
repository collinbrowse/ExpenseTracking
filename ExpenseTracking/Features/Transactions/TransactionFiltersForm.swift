import SwiftUI
import CashFlowKit

/// Shared account / date / category / tag pickers for Transactions and CSV export.
/// Embed inside a `Form` or `List`.
struct TransactionFiltersForm: View {
    @Bindable var filters: TransactionFilterSession
    let accounts: [Account]
    let tags: [Tag]
    var accessibilityPrefix: String

    var body: some View {
        Section("Account") {
            Picker("Account", selection: $filters.accountID) {
                Text("All").tag(Optional<AccountID>.none)
                ForEach(accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            .accessibilityIdentifier("\(accessibilityPrefix).account")
        }

        Section("Date") {
            Picker("Date", selection: $filters.dateOption) {
                ForEach(TransactionDateFilterOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .accessibilityIdentifier("\(accessibilityPrefix).date")

            if filters.dateOption == .custom {
                DatePicker("Start", selection: $filters.customStart, displayedComponents: .date)
                DatePicker("End", selection: $filters.customEnd, displayedComponents: .date)
            }
        }

        Section("Category") {
            Picker("Category", selection: $filters.categoryID) {
                Text("All").tag(Optional<CategoryID>.none)
                ForEach(SystemCategory.allCategories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            .accessibilityIdentifier("\(accessibilityPrefix).category")
        }

        Section("Tag") {
            Picker("Tag", selection: $filters.tagID) {
                Text("All").tag(Optional<TagID>.none)
                ForEach(tags) { tag in
                    Text(tag.name).tag(Optional(tag.id))
                }
            }
            .accessibilityIdentifier("\(accessibilityPrefix).tag")
        }
    }
}
