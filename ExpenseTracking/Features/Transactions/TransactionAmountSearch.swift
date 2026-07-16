import Foundation

enum TransactionAmountSearch {
    /// Logical amount search: `"66"` matches `"$66.43"`, `"−$166.00"`, etc.
    static func matches(_ query: String, amountText: String) -> Bool {
        let queryNumeric = String(query.filter { $0.isNumber || $0 == "." })
        guard !queryNumeric.isEmpty else { return false }
        let amountNumeric = String(amountText.filter { $0.isNumber || $0 == "." })
        guard !amountNumeric.isEmpty else { return false }
        return amountNumeric.contains(queryNumeric)
    }
}
