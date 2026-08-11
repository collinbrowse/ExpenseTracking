import Foundation
import Testing
@testable import CashFlowKit

@Suite("TransactionSearchMatching")
struct TransactionSearchMatchingTests {
    @Test("Amount digit matching")
    func amountDigits() {
        #expect(TransactionSearchMatching.matchesAmount("66", amountText: "$66.43"))
        #expect(TransactionSearchMatching.matchesAmount("66", amount: Decimal(string: "66.43")!))
        #expect(!TransactionSearchMatching.matchesAmount("67", amountText: "$66.43"))
    }

    @Test("Text fields match case-insensitively")
    func textFields() {
        #expect(
            TransactionSearchMatching.matches(
                query: "starbucks",
                title: "Starbucks",
                location: "Denver",
                description: "STARBUCKS #1",
                categoryName: "Dining",
                tagNames: ["Trip"],
                accountName: "Checking",
                amount: -12
            )
        )
        #expect(
            TransactionSearchMatching.matches(
                query: "trip",
                title: nil,
                location: nil,
                description: "x",
                categoryName: "Other",
                tagNames: ["Trip"],
                accountName: "Checking",
                amount: -1
            )
        )
        #expect(
            !TransactionSearchMatching.matches(
                query: "zzz",
                title: "Coffee",
                location: nil,
                description: "COFFEE",
                categoryName: "Dining",
                tagNames: [],
                accountName: "Checking",
                amount: -5
            )
        )
    }
}
