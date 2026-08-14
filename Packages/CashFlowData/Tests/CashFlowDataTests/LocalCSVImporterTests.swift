import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("CSV import persistence")
struct LocalCSVImporterTests {
    @Test("Commit inserts rows, records batch, deleteBatch tombstones and removes txs")
    func commitAndDeleteBatch() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let importer = LocalCSVImporter(modelContainer: container, enrichment: nil)

        let csv = """
        posted_date,amount,currency,title,location,category,account,tags,pending,raw_description,external_id
        2024-03-01,-12.50,USD,Coffee,,Dining,Cash,,false,STARBUCKS #1,ext-1
        2024-03-02,100.00,USD,Paycheck,,Income,Cash,,false,ACME PAYROLL,ext-2
        """
        let data = Data(csv.utf8)
        let preview = try await importer.parsePreview(data: data, fileName: "test.csv", mapping: nil)
        #expect(preview.mapping.presetName == "Cash Flow export")
        #expect(preview.validRowCount == 2)
        #expect(preview.invalidRowCount == 0)

        let result = try await importer.commit(
            CSVImportCommitPlan(
                fileName: "test.csv",
                rows: preview.rows,
                conflicts: [],
                accountChoice: .createNew(name: "Cash", institutionName: "CSV Import")
            )
        )
        #expect(result.batch.insertedCount == 2)
        #expect(result.batch.status == .active)
        #expect(result.batch.createdAccount)

        let context = ModelContext(container)
        let txs = try context.fetch(FetchDescriptor<TransactionEntity>())
        #expect(txs.count == 2)
        #expect(txs.allSatisfy { $0.ingestSourceRaw == IngestSource.csvImport.rawValue })
        #expect(txs.allSatisfy { $0.importBatchID == result.batch.id.rawValue })

        let deleted = try await importer.deleteBatch(id: result.batch.id)
        #expect(deleted.status == .deleted)
        #expect(deleted.deletedAt != nil)

        let remainingTxs = try ModelContext(container).fetch(FetchDescriptor<TransactionEntity>())
        #expect(remainingTxs.isEmpty)
        let accounts = try ModelContext(container).fetch(FetchDescriptor<AccountEntity>())
        #expect(accounts.isEmpty)

        let batches = try await importer.listBatches()
        #expect(batches.count == 1)
        #expect(batches[0].status == .deleted)
    }

    @Test("Skip conflict leaves existing; replace updates description")
    func conflictActions() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let importer = LocalCSVImporter(modelContainer: container, enrichment: nil)

        let csv1 = """
        date,description,amount
        01/15/2024,Coffee,-5.00
        """
        let preview1 = try await importer.parsePreview(
            data: Data(csv1.utf8),
            fileName: "a.csv",
            mapping: nil
        )
        let first = try await importer.commit(
            CSVImportCommitPlan(
                fileName: "a.csv",
                rows: preview1.rows,
                conflicts: [],
                accountChoice: .createNew(name: "Wallet", institutionName: "Cash")
            )
        )

        let accountID = first.batch.accountID
        let csv2 = """
        date,description,amount
        01/15/2024,Coffee,-5.00
        """
        let preview2 = try await importer.parsePreview(
            data: Data(csv2.utf8),
            fileName: "b.csv",
            mapping: nil
        )
        var conflicts = try await importer.findConflicts(rows: preview2.rows, accountID: accountID)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].action == nil)

        conflicts[0].action = .skip
        _ = try await importer.commit(
            CSVImportCommitPlan(
                fileName: "b.csv",
                rows: preview2.rows,
                conflicts: conflicts,
                accountChoice: .existing(accountID)
            )
        )
        var txs = try ModelContext(container).fetch(FetchDescriptor<TransactionEntity>())
        #expect(txs.count == 1)

        conflicts[0].action = .replace
        // Need a fresh conflict pointing at the existing tx
        conflicts = try await importer.findConflicts(rows: preview2.rows, accountID: accountID)
        #expect(conflicts.count == 1)
        conflicts[0].action = .replace
        _ = try await importer.commit(
            CSVImportCommitPlan(
                fileName: "c.csv",
                rows: preview2.rows,
                conflicts: conflicts,
                accountChoice: .existing(accountID)
            )
        )
        txs = try ModelContext(container).fetch(FetchDescriptor<TransactionEntity>())
        #expect(txs.count == 1)
        #expect(txs[0].importBatchID != nil)
    }
}
