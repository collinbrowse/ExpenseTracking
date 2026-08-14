import Foundation
import CashFlowKit

struct TransactionRowModel: Identifiable, Hashable, Sendable {
    let id: TransactionID
    let accountID: AccountID
    /// Merchant / payee from enrichment, else raw bank description.
    let title: String
    /// Location from enrichment when present.
    let location: String?
    /// Immutable bank description for search and the editor's muted raw line.
    let rawDescription: String
    let categoryText: String
    let categoryID: CategoryID
    let categoryLocked: Bool
    let tagIDs: [TagID]
    /// Chip labels for the row (up to two names, then optional “+N”).
    let tagChipLabels: [String]
    /// Joined labels for search.
    var tagText: String? {
        tagChipLabels.isEmpty ? nil : tagChipLabels.joined(separator: " ")
    }
    let dateText: String
    let amountText: String
    let amountIsIncome: Bool
    let accountName: String
    let postedDate: Date
    /// Kept so edits can rebuild amount styling without a full list reload.
    let amount: Decimal
    let isPending: Bool
    let ingestSource: IngestSource
    /// Stable month bucket for section headers, e.g. `2026-07`.
    let sectionKey: String
    let sectionTitle: String

    init(
        transaction: Transaction,
        accountName: String,
        tagNamesByID: [TagID: String] = [:],
        calendar: Calendar = .current
    ) {
        self.id = transaction.id
        self.accountID = transaction.accountID
        self.title = transaction.displayTitle
        self.location = transaction.displayLocation
        self.rawDescription = transaction.description
        self.categoryText = transaction.category.name
        self.categoryID = transaction.categoryID
        self.categoryLocked = transaction.categoryLocked
        self.tagIDs = transaction.tagIDs
        self.tagChipLabels = Self.formatTagChipLabels(
            tagIDs: transaction.tagIDs,
            names: tagNamesByID
        )
        // Pending rows live under a dedicated section header; show the authorization date here.
        self.dateText = DateFormatting.list(transaction.postedDate)
        self.accountName = accountName
        self.postedDate = transaction.postedDate
        self.amount = transaction.amount
        self.isPending = transaction.isPending
        self.ingestSource = transaction.ingestSource

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

    /// Rebuilds display fields after a local enrichment edit without refetching the list.
    func replacing(
        title: String,
        location: String?,
        categoryID: CategoryID,
        categoryLocked: Bool,
        tagIDs: [TagID]? = nil,
        tagNamesByID: [TagID: String] = [:]
    ) -> TransactionRowModel {
        let resolvedTags = tagIDs ?? self.tagIDs
        let transaction = Transaction(
            id: id,
            accountID: accountID,
            externalID: "",
            amount: amount,
            postedDate: postedDate,
            description: rawDescription,
            categoryID: categoryID,
            userEditedCategory: true,
            isPending: isPending,
            categoryLocked: categoryLocked,
            tagIDs: resolvedTags,
            enrichedTitle: title,
            enrichedLocation: location,
            titleSource: .user,
            categorySource: .user,
            ingestSource: ingestSource
        )
        return TransactionRowModel(
            transaction: transaction,
            accountName: accountName,
            tagNamesByID: tagNamesByID
        )
    }

    private static func formatTagChipLabels(tagIDs: [TagID], names: [TagID: String]) -> [String] {
        let resolved = tagIDs.compactMap { names[$0] }
        guard !resolved.isEmpty else { return [] }
        if resolved.count <= 2 {
            return resolved
        }
        return [resolved[0], resolved[1], "+\(resolved.count - 2)"]
    }
}

struct TransactionMonthSection: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let title: String
    let rows: [TransactionRowModel]
}
