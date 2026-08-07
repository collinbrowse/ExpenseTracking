import Foundation

/// Store- and UI-shared text/amount matching for transaction search.
public enum TransactionSearchMatching: Sendable {
    /// Logical amount search: `"66"` matches `"$66.43"`, `"−$166.00"`, etc.
    public static func matchesAmount(_ query: String, amountText: String) -> Bool {
        let queryNumeric = String(query.filter { $0.isNumber || $0 == "." })
        guard !queryNumeric.isEmpty else { return false }
        let amountNumeric = String(amountText.filter { $0.isNumber || $0 == "." })
        guard !amountNumeric.isEmpty else { return false }
        return amountNumeric.contains(queryNumeric)
    }

    public static func matchesAmount(_ query: String, amount: Decimal) -> Bool {
        matchesAmount(query, amountText: "\(amount)")
    }

    /// Case-insensitive contains across title, location, bank description, category, tags, account, amount.
    public static func matches(
        query: String,
        title: String?,
        location: String?,
        description: String,
        categoryName: String,
        tagNames: [String],
        accountName: String,
        amount: Decimal
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if let title, title.localizedCaseInsensitiveContains(trimmed) { return true }
        if let location, location.localizedCaseInsensitiveContains(trimmed) { return true }
        if description.localizedCaseInsensitiveContains(trimmed) { return true }
        if categoryName.localizedCaseInsensitiveContains(trimmed) { return true }
        if tagNames.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) { return true }
        if accountName.localizedCaseInsensitiveContains(trimmed) { return true }
        if matchesAmount(trimmed, amount: amount) { return true }
        return false
    }
}
