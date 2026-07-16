import Testing
@testable import ExpenseTracking

@Suite("Amount search")
struct AmountSearchTests {
    @Test("Digits match formatted currency")
    func digitsMatchCurrency() {
        #expect(TransactionAmountSearch.matches("66", amountText: "$66.43"))
        #expect(TransactionAmountSearch.matches("66.43", amountText: "$66.43"))
        #expect(TransactionAmountSearch.matches("66", amountText: "−$66.43"))
        #expect(!TransactionAmountSearch.matches("67", amountText: "$66.43"))
        #expect(!TransactionAmountSearch.matches("abc", amountText: "$66.43"))
    }
}
