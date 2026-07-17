import Foundation
import CashFlowKit

struct TransactionRowModel: Identifiable, Hashable, Sendable {
    let id: TransactionID
    /// Merchant / payee without trailing bank location padding.
    let title: String
    /// City / region when SimpleFIN pads it after the merchant name.
    let location: String?
    let categoryText: String
    let categoryID: CategoryID
    let dateText: String
    let amountText: String
    let amountIsIncome: Bool
    let accountName: String
    let postedDate: Date
    /// Kept so edits can rebuild amount styling without a full list reload.
    let amount: Decimal
    let isPending: Bool
    /// Stable month bucket for section headers, e.g. `2026-07`.
    let sectionKey: String
    let sectionTitle: String

    init(transaction: Transaction, accountName: String, calendar: Calendar = .current) {
        let parsed = ParseTransactionDescriptionUseCase.execute(transaction.description)
        self.id = transaction.id
        self.title = parsed.title
        self.location = parsed.location
        self.categoryText = transaction.category.name
        self.categoryID = transaction.categoryID
        self.dateText = DateFormatting.list(transaction.postedDate)
        self.accountName = accountName
        self.postedDate = transaction.postedDate
        self.amount = transaction.amount
        self.isPending = transaction.isPending

        let components = calendar.dateComponents([.year, .month], from: transaction.postedDate)
        let year = components.year ?? 0
        let month = components.month ?? 0
        self.sectionKey = String(format: "%04d-%02d", year, month)
        self.sectionTitle = transaction.postedDate.formatted(.dateTime.month(.wide).year())

        let contribution = CashFlowContribution.forTransaction(transaction)
        switch contribution {
        case .income:
            // Reference style: green amount without leading "+".
            self.amountText = CurrencyFormatting.usd(abs(transaction.amount))
            self.amountIsIncome = true
        case .expense:
            self.amountText = "−\(CurrencyFormatting.usd(abs(transaction.amount)))"
            self.amountIsIncome = false
        case .none:
            let signed = transaction.amount
            if signed > 0 {
                self.amountText = CurrencyFormatting.usd(signed)
                self.amountIsIncome = true
            } else if signed < 0 {
                self.amountText = "−\(CurrencyFormatting.usd(abs(signed)))"
                self.amountIsIncome = false
            } else {
                self.amountText = CurrencyFormatting.usd(0)
                self.amountIsIncome = false
            }
        }
    }

    /// Rebuilds display fields after a local edit without refetching the list.
    func replacing(description: String, categoryID: CategoryID) -> TransactionRowModel {
        let transaction = Transaction(
            id: id,
            accountID: AccountID(""),
            externalID: "",
            amount: amount,
            postedDate: postedDate,
            description: description,
            categoryID: categoryID,
            userEditedCategory: true,
            isPending: isPending
        )
        return TransactionRowModel(transaction: transaction, accountName: accountName)
    }
}

struct TransactionMonthSection: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let title: String
    let rows: [TransactionRowModel]
}
