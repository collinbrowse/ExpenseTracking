import Foundation

import CashFlowKit

/// Thin wrapper kept for Feature call sites; matching lives in CashFlowKit.
enum TransactionAmountSearch {
    static func matches(_ query: String, amountText: String) -> Bool {
        TransactionSearchMatching.matchesAmount(query, amountText: amountText)
    }
}
