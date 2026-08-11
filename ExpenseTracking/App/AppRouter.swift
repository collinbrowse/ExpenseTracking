import Foundation
import Observation
import CashFlowKit

enum AppTab: Hashable {
    case home
    case transactions
    case insights
    case settings
}

/// Cross-tab navigation focus for the Transactions list.
enum TransactionsFocusRequest: Hashable, Sendable {
    case account(AccountID)
    case insights(
        categoryID: CategoryID?,
        tagID: TagID?,
        dateOption: TransactionDateFilterOption,
        customStart: Date,
        customEnd: Date
    )
}

enum HomeRoute: Hashable {
    case transactionDetail(String)
}

enum TransactionRoute: Hashable {
    case detail(String)
}

enum AccountsRoute: Hashable {
    case link
}

/// Typed tab + transactions focus router (shared by RootTabView).
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var pendingTransactionsFocus: TransactionsFocusRequest?

    func openAccountTransactions(_ accountID: AccountID) {
        pendingTransactionsFocus = .account(accountID)
        selectedTab = .transactions
    }

    func openInsightsTransactions(
        categoryID: CategoryID?,
        tagID: TagID?,
        dateOption: TransactionDateFilterOption,
        customStart: Date,
        customEnd: Date
    ) {
        pendingTransactionsFocus = .insights(
            categoryID: categoryID,
            tagID: tagID,
            dateOption: dateOption,
            customStart: customStart,
            customEnd: customEnd
        )
        selectedTab = .transactions
    }

    func consumeTransactionsFocus() -> TransactionsFocusRequest? {
        let value = pendingTransactionsFocus
        pendingTransactionsFocus = nil
        return value
    }
}
