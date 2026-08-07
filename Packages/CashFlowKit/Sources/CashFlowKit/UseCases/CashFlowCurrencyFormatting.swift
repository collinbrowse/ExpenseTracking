import Foundation

/// Shared USD formatting for Home, widgets, and tests (Decimal only).
public enum CashFlowCurrencyFormatting {
    public static func usd(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "USD"))
    }

    /// Signed net: `+$1.00` / `−$1.00` / `$0.00`.
    public static func signedUSD(_ amount: Decimal) -> String {
        let formatted = usd(abs(amount))
        if amount > 0 { return "+\(formatted)" }
        if amount < 0 { return "−\(formatted)" }
        return formatted
    }

    /// Widget income row — always shown with a leading plus.
    public static func signedIncomeUSD(_ amount: Decimal) -> String {
        "+\(usd(abs(amount)))"
    }

    /// Widget expense row — always shown with a leading minus (amount is an absolute total).
    public static func signedExpenseUSD(_ amount: Decimal) -> String {
        "−\(usd(abs(amount)))"
    }
}
