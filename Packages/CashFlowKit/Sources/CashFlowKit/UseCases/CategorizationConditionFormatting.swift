import Foundation

public enum CategorizationConditionFormatting: Sendable {
    public static func summary(
        for conditions: [CategorizationCondition],
        accountName: (AccountID) -> String = { _ in "Account" },
        categoryName: (CategoryID) -> String = { SystemCategory.category(for: $0).name },
        tagName: (TagID) -> String = { _ in "Tag" }
    ) -> String {
        conditions
            .map { summary(for: $0, accountName: accountName, categoryName: categoryName, tagName: tagName) }
            .joined(separator: " · ")
    }

    public static func summary(
        for condition: CategorizationCondition,
        accountName: (AccountID) -> String = { _ in "Account" },
        categoryName: (CategoryID) -> String = { SystemCategory.category(for: $0).name },
        tagName: (TagID) -> String = { _ in "Tag" }
    ) -> String {
        switch condition {
        case .titleContains(let value):
            return "Title contains “\(value)”"
        case .titleEquals(let value):
            return "Title is “\(value)”"
        case .descriptionContains(let value):
            return "Description contains “\(value)”"
        case .descriptionEquals(let value):
            return "Description is “\(value)”"
        case .locationContains(let value):
            return "Location contains “\(value)”"
        case .categoryIs(let id):
            return "Category is \(categoryName(id))"
        case .hasTag(let id):
            return "Has tag \(tagName(id))"
        case .accountID(let id):
            return "Account is \(accountName(id))"
        case .amountMin(let min):
            return "Amount ≥ \(formatAmount(min))"
        case .amountMax(let max):
            return "Amount ≤ \(formatAmount(max))"
        }
    }

    private static func formatAmount(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: number) ?? "\(value)"
    }
}
