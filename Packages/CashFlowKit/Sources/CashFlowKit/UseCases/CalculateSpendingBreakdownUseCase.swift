import Foundation

/// Ranked spending total for a category or tag within a date range.
public struct SpendingSlice: Identifiable, Hashable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let total: Decimal

    public init(id: String, name: String, total: Decimal) {
        self.id = id
        self.name = name
        self.total = total
    }
}

public struct SpendingBreakdownResult: Sendable, Equatable {
    public let byCategory: [SpendingSlice]
    public let byTag: [SpendingSlice]
    public let expenseTotal: Decimal

    public init(byCategory: [SpendingSlice], byTag: [SpendingSlice], expenseTotal: Decimal) {
        self.byCategory = byCategory
        self.byTag = byTag
        self.expenseTotal = expenseTotal
    }
}

/// Optional AND-scoped filters for Insights (e.g. Fees within “Japan Trip”).
public struct SpendingBreakdownScope: Hashable, Sendable, Equatable {
    public var categoryID: CategoryID?
    public var tagID: TagID?

    public init(categoryID: CategoryID? = nil, tagID: TagID? = nil) {
        self.categoryID = categoryID
        self.tagID = tagID
    }

    public static let all = SpendingBreakdownScope()

    public var isFiltered: Bool {
        categoryID != nil || tagID != nil
    }
}

/// Aggregates expense outflows by category and by tag for Insights.
///
/// Only `.expense` contributions count (pending / excluded / income → 0), matching Home “Out”.
/// A multi-tagged expense’s full amount is counted toward **each** of its tags.
/// Optional `scope` applies category and tag filters with AND semantics.
public struct CalculateSpendingBreakdownUseCase: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func execute(
        transactions: [Transaction],
        tags: [Tag],
        range: CashFlowDateRange,
        scope: SpendingBreakdownScope = .all,
        now: Date = .now
    ) -> SpendingBreakdownResult {
        let interval = range.interval(calendar: calendar, now: now)
        let tagNames = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })

        var categoryTotals: [CategoryID: Decimal] = [:]
        var tagTotals: [TagID: Decimal] = [:]
        var expenseTotal: Decimal = 0

        for transaction in transactions {
            guard CashFlowContribution.forTransaction(transaction) == .expense else { continue }
            guard transaction.postedDate >= interval.start,
                  transaction.postedDate <= interval.end
            else { continue }
            if let categoryID = scope.categoryID, transaction.categoryID != categoryID {
                continue
            }
            if let tagID = scope.tagID, !transaction.tagIDs.contains(tagID) {
                continue
            }

            let amount = abs(transaction.amount)
            expenseTotal += amount
            categoryTotals[transaction.categoryID, default: 0] += amount

            for id in transaction.tagIDs {
                tagTotals[id, default: 0] += amount
            }
        }

        let byCategory = categoryTotals
            .map { id, total in
                SpendingSlice(
                    id: id.rawValue,
                    name: SystemCategory.category(for: id).name,
                    total: total
                )
            }
            .sorted(by: Self.sliceSort)

        let byTag = tagTotals
            .compactMap { id, total -> SpendingSlice? in
                guard let name = tagNames[id] else { return nil }
                return SpendingSlice(id: id.rawValue, name: name, total: total)
            }
            .sorted(by: Self.sliceSort)

        return SpendingBreakdownResult(
            byCategory: byCategory,
            byTag: byTag,
            expenseTotal: expenseTotal
        )
    }

    private static func sliceSort(_ lhs: SpendingSlice, _ rhs: SpendingSlice) -> Bool {
        if lhs.total != rhs.total {
            return lhs.total > rhs.total
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
