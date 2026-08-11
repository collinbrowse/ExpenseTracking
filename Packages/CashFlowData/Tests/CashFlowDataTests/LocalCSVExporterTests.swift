import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("LocalCSVExporter")
struct LocalCSVExporterTests {
    @Test("CSV includes matching transactions and respects account filter")
    func exportRespectsFilter() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)

        let checking = AccountEntity(
            id: "checking",
            externalID: "ext-c",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 100,
            balanceDate: .now
        )
        let card = AccountEntity(
            id: "card",
            externalID: "ext-d",
            name: "Card",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: -10,
            balanceDate: .now
        )
        context.insert(checking)
        context.insert(card)
        context.insert(
            TransactionEntity(
                id: "tx1",
                externalID: "u1",
                accountID: checking.id,
                amount: -12.5,
                postedDate: Date(timeIntervalSince1970: 1_700_000_100),
                transactionDescription: "COFFEE SHOP",
                categoryID: SystemCategory.dining.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext-c|u1",
                account: checking,
                enrichedTitle: "Coffee Shop",
                categorySourceRaw: CategorySource.keyword.rawValue
            )
        )
        context.insert(
            TransactionEntity(
                id: "tx2",
                externalID: "u2",
                accountID: card.id,
                amount: -40,
                postedDate: Date(timeIntervalSince1970: 1_700_000_200),
                transactionDescription: "GAS",
                categoryID: SystemCategory.transport.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext-d|u2",
                account: card
            )
        )
        try context.save()

        let exporter = LocalCSVExporter(modelContainer: container)
        let allData = try await exporter.exportCSV(filter: .all)
        let allCSV = try #require(String(data: allData, encoding: .utf8))
        #expect(allCSV.contains("posted_date,amount,currency,title"))
        #expect(allCSV.contains("Coffee Shop"))
        #expect(allCSV.contains("GAS"))

        let filtered = try await exporter.exportCSV(
            filter: TransactionFilter(accountID: AccountID("checking"))
        )
        let filteredCSV = try #require(String(data: filtered, encoding: .utf8))
        #expect(filteredCSV.contains("Coffee Shop"))
        #expect(!filteredCSV.contains("GAS"))
        #expect(filteredCSV.contains("-12.5"))
    }

    @Test("Empty filter match yields header-only CSV")
    func emptyExport() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let data = try await LocalCSVExporter(modelContainer: container).exportCSV(filter: .all)
        let csv = try #require(String(data: data, encoding: .utf8))
        #expect(csv.hasPrefix("posted_date,amount,currency,title"))
        #expect(csv.split(separator: "\n").count == 1)
    }
}
