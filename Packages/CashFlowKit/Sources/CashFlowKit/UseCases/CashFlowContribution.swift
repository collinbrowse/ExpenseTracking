import Foundation

/// Determines how a transaction contributes to net cash flow.
public enum CashFlowContribution: Sendable {
    /// Positive contribution (income). Uses absolute value of amount when needed.
    case income
    /// Negative contribution (expense). Uses absolute value of amount as outflow.
    case expense
    /// Zero contribution (Hidden, Transfer, Credit Card Payment, pending).
    case none

    public static func forCategory(_ category: Category) -> CashFlowContribution {
        switch category.kind {
        case .income: .income
        case .expense: .expense
        case .excluded: .none
        }
    }

    public static func forTransaction(_ transaction: Transaction) -> CashFlowContribution {
        if transaction.isPending { return .none }
        return forCategory(transaction.category)
    }

    /// Signed contribution toward net (income positive, expense negative, excluded zero).
    public func signedAmount(of amount: Decimal) -> Decimal {
        let magnitude = abs(amount)
        switch self {
        case .income: return magnitude
        case .expense: return -magnitude
        case .none: return 0
        }
    }
}
