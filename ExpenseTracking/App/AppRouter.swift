import Foundation

enum AppTab: Hashable {
    case home
    case transactions
    case insights
    case accounts
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
