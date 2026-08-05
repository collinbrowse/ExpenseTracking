import Foundation
import Testing
@testable import CashFlowKit

@Suite("CalculateSpendingBreakdownUseCase")
struct CalculateSpendingBreakdownUseCaseTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    private var useCase: CalculateSpendingBreakdownUseCase {
        CalculateSpendingBreakdownUseCase(calendar: calendar)
    }

    private let accountID = AccountID("acct-1")
    private let now = Date(timeIntervalSince1970: 1_720_000_000)
    private let trip = Tag(id: TagID("tag-trip"), name: "Japan Trip", createdAt: .distantPast)
    private let concert = Tag(id: TagID("tag-concert"), name: "Local Concert", createdAt: .distantPast)

    private func tx(
        id: String,
        amount: Decimal,
        daysAgo: Int,
        category: SystemCategory,
        tagIDs: [TagID] = [],
        pending: Bool = false
    ) -> Transaction {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return Transaction(
            id: TransactionID(id),
            accountID: accountID,
            externalID: id,
            amount: amount,
            postedDate: date,
            description: id,
            categoryID: category.id,
            isPending: pending,
            tagIDs: tagIDs
        )
    }

    @Test("Groups expenses by category; ignores income, excluded, and pending")
    func categoryBreakdown() {
        let transactions = [
            tx(id: "1", amount: 3000, daysAgo: 2, category: .income),
            tx(id: "2", amount: -50, daysAgo: 1, category: .groceries),
            tx(id: "3", amount: -25, daysAgo: 1, category: .dining),
            tx(id: "4", amount: -100, daysAgo: 1, category: .transfer),
            tx(id: "5", amount: -10, daysAgo: 1, category: .groceries, pending: true),
        ]
        let result = useCase.execute(
            transactions: transactions,
            tags: [trip, concert],
            range: .last30Days,
            now: now
        )
        #expect(result.expenseTotal == 75)
        #expect(result.byCategory.map(\.id) == [
            SystemCategory.groceries.id.rawValue,
            SystemCategory.dining.id.rawValue,
        ])
        #expect(result.byCategory[0].total == 50)
        #expect(result.byCategory[1].total == 25)
        #expect(result.byTag.isEmpty)
    }

    @Test("Multi-tagged expense counts full amount toward each tag")
    func multiTagDoubleCounts() {
        let transactions = [
            tx(
                id: "1",
                amount: -100,
                daysAgo: 1,
                category: .shopping,
                tagIDs: [trip.id, concert.id]
            ),
            tx(
                id: "2",
                amount: -40,
                daysAgo: 1,
                category: .dining,
                tagIDs: [trip.id]
            ),
        ]
        let result = useCase.execute(
            transactions: transactions,
            tags: [trip, concert],
            range: .last30Days,
            now: now
        )
        #expect(result.expenseTotal == 140)
        #expect(result.byTag.count == 2)
        let byID = Dictionary(uniqueKeysWithValues: result.byTag.map { ($0.id, $0.total) })
        #expect(byID[trip.id.rawValue] == 140)
        #expect(byID[concert.id.rawValue] == 100)
    }

    @Test("Omits unknown tag IDs from byTag slices")
    func unknownTagsOmitted() {
        let transactions = [
            tx(
                id: "1",
                amount: -20,
                daysAgo: 1,
                category: .other,
                tagIDs: [TagID("missing")]
            ),
        ]
        let result = useCase.execute(
            transactions: transactions,
            tags: [trip],
            range: .last30Days,
            now: now
        )
        #expect(result.byTag.isEmpty)
        #expect(result.expenseTotal == 20)
    }

    @Test("Respects date range")
    func dateRangeFilter() {
        let transactions = [
            tx(id: "old", amount: -80, daysAgo: 40, category: .shopping, tagIDs: [trip.id]),
            tx(id: "new", amount: -30, daysAgo: 1, category: .shopping, tagIDs: [trip.id]),
        ]
        let result = useCase.execute(
            transactions: transactions,
            tags: [trip],
            range: .last30Days,
            now: now
        )
        #expect(result.expenseTotal == 30)
        #expect(result.byTag.first?.total == 30)
    }

    @Test("Scope ANDs category and tag filters")
    func categoryAndTagScope() {
        let transactions = [
            tx(
                id: "1",
                amount: -50,
                daysAgo: 1,
                category: .feesCharges,
                tagIDs: [trip.id]
            ),
            tx(
                id: "2",
                amount: -20,
                daysAgo: 1,
                category: .dining,
                tagIDs: [trip.id]
            ),
            tx(
                id: "3",
                amount: -15,
                daysAgo: 1,
                category: .feesCharges,
                tagIDs: [concert.id]
            ),
        ]
        let result = useCase.execute(
            transactions: transactions,
            tags: [trip, concert],
            range: .last30Days,
            scope: SpendingBreakdownScope(
                categoryID: SystemCategory.feesCharges.id,
                tagID: trip.id
            ),
            now: now
        )
        #expect(result.expenseTotal == 50)
        #expect(result.byCategory.map(\.id) == [SystemCategory.feesCharges.id.rawValue])
        #expect(result.byTag.map(\.id) == [trip.id.rawValue])
    }

    @Test("Tag-only scope still breaks down categories within the tag")
    func tagScopeCategoryBreakdown() {
        let transactions = [
            tx(id: "1", amount: -50, daysAgo: 1, category: .feesCharges, tagIDs: [trip.id]),
            tx(id: "2", amount: -20, daysAgo: 1, category: .dining, tagIDs: [trip.id]),
            tx(id: "3", amount: -99, daysAgo: 1, category: .feesCharges, tagIDs: []),
        ]
        let result = useCase.execute(
            transactions: transactions,
            tags: [trip],
            range: .last30Days,
            scope: SpendingBreakdownScope(tagID: trip.id),
            now: now
        )
        #expect(result.expenseTotal == 70)
        #expect(result.byCategory.count == 2)
        #expect(result.byCategory[0].total == 50)
        #expect(result.byCategory[1].total == 20)
    }
}
