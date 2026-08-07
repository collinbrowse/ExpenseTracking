import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("LocalJSONExporter")
struct LocalJSONExporterTests {
    @Test("Export includes accounts, transactions, tags, rules, and connection metadata")
    func exportRoundTripEnvelope() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)

        let account = AccountEntity(
            id: "acct",
            externalID: "ext-a",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 100,
            balanceDate: Date(timeIntervalSince1970: 1_700_000_000),
            userEditedName: true,
            connectionExternalID: "conn-1"
        )
        context.insert(account)
        context.insert(
            TransactionEntity(
                id: "tx1",
                externalID: "u1",
                accountID: account.id,
                amount: -12.5,
                postedDate: Date(timeIntervalSince1970: 1_700_000_100),
                transactionDescription: "COFFEE",
                categoryID: SystemCategory.dining.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: true,
                isPending: false,
                syncKey: "ext-a|u1",
                account: account,
                categorySourceRaw: CategorySource.user.rawValue
            )
        )
        context.insert(
            TagEntity(id: "tag1", name: "Trip", createdAt: Date(timeIntervalSince1970: 1_700_000_050))
        )
        let conditions = try EntityMappers.encodeConditions([.titleContains("Coffee")])
        context.insert(
            CategorizationRuleEntity(
                id: "r1",
                categoryID: SystemCategory.dining.id.rawValue,
                priority: 0,
                isEnabled: true,
                conditionsData: conditions
            )
        )
        context.insert(
            ConnectionEntity(
                id: "conn",
                providerName: "Demo",
                needsReauth: false,
                lastSuccessfulSyncAt: Date(timeIntervalSince1970: 1_700_000_200),
                isDemo: true,
                earliestFetchedDate: Date(timeIntervalSince1970: 1_600_000_000),
                lookbackYearsRaw: 2,
                historyComplete: true
            )
        )
        try context.save()

        let data = try await LocalJSONExporter(modelContainer: container).exportJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(LocalDataExportDocument.self, from: data)

        #expect(document.formatVersion == LocalDataExportDocument.currentFormatVersion)
        #expect(document.accounts.count == 1)
        #expect(document.accounts[0].userEditedName == true)
        #expect(document.accounts[0].connectionExternalID == "conn-1")
        #expect(document.transactions.count == 1)
        #expect(document.transactions[0].categorySource == .user)
        #expect(document.tags.map(\.name) == ["Trip"])
        #expect(document.rules.count == 1)
        #expect(document.connection?.isDemo == true)
        #expect(document.connection?.providerName == "Demo")
        #expect(document.connection?.historyComplete == true)
    }

    @Test("Empty store exports a valid empty envelope")
    func emptyStore() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let data = try await LocalJSONExporter(modelContainer: container).exportJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(LocalDataExportDocument.self, from: data)
        #expect(document.accounts.isEmpty)
        #expect(document.transactions.isEmpty)
        #expect(document.tags.isEmpty)
        #expect(document.rules.isEmpty)
        #expect(document.connection == nil)
    }
}
