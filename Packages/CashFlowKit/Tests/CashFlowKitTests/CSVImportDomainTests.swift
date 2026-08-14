import Foundation
import Testing
import CashFlowKit

@Suite("CSV import domain")
struct CSVImportDomainTests {
    @Test("Detects Cash Flow export headers")
    func detectsOurExport() {
        let headers = [
            "posted_date", "amount", "currency", "title", "location", "category",
            "account", "tags", "pending", "raw_description", "external_id",
        ]
        let mapping = DetectCSVColumnMappingUseCase().execute(headers: headers)
        #expect(mapping.presetName == "Cash Flow export")
        #expect(mapping.isReady)
        #expect(mapping.assignments.values.contains(.postedDate))
        #expect(mapping.assignments.values.contains(.amount))
        #expect(mapping.assignments.values.contains(.description))
    }

    @Test("Parses amounts with parentheses and currency symbols")
    func parsesAmounts() {
        #expect(ParseCSVAmountUseCase.parse("($12.34)") == Decimal(string: "-12.34"))
        #expect(ParseCSVAmountUseCase.parse("$1,234.50") == Decimal(string: "1234.50"))
        #expect(ParseCSVAmountUseCase.fromDebitCredit(debit: "10.00", credit: nil) == Decimal(string: "-10"))
        #expect(ParseCSVAmountUseCase.fromDebitCredit(debit: nil, credit: "5.00") == Decimal(string: "5"))
    }

    @Test("Fingerprint conflicts default to unset; bulk skip then replace updates all")
    func conflictBulk() {
        let row = CSVImportRow(
            rowIndex: 2,
            postedDate: Date(timeIntervalSince1970: 1_700_000_000),
            amount: -12,
            description: "Coffee"
        )
        var conflicts = [
            CSVImportConflict(
                importRow: row,
                existingTransactionID: TransactionID("t1"),
                existingDescription: "Coffee",
                existingAmount: -12,
                existingPostedDate: row.postedDate,
                action: nil
            ),
        ]
        let useCase = ResolveImportConflictsUseCase()
        #expect(!useCase.allResolved(conflicts))
        useCase.applyBulk(.skip, to: &conflicts)
        #expect(conflicts.allSatisfy { $0.action == .skip })
        #expect(useCase.allResolved(conflicts))
        useCase.applyBulk(.replace, to: &conflicts)
        #expect(conflicts.allSatisfy { $0.action == .replace })
        #expect(useCase.replacements(conflicts: conflicts).count == 1)
        #expect(useCase.skippedCount(conflicts: conflicts) == 0)
    }

    @Test("Match fingerprints on same day amount description account")
    func matchFingerprints() {
        let accountID = AccountID("a1")
        let date = ParseCSVDateUseCase.parse("2024-01-15")!
        let existing = Transaction(
            id: TransactionID("t1"),
            accountID: accountID,
            externalID: "e1",
            amount: Decimal(string: "-42.00")!,
            postedDate: date,
            description: "Grocery Store",
            categoryID: SystemCategory.undefined.id
        )
        let row = CSVImportRow(
            rowIndex: 2,
            postedDate: date,
            amount: Decimal(string: "-42.00")!,
            description: "Grocery Store"
        )
        let conflicts = MatchImportFingerprintsUseCase().execute(
            rows: [row],
            accountID: accountID,
            existing: [existing]
        )
        #expect(conflicts.count == 1)
        #expect(conflicts[0].existingTransactionID == existing.id)
        #expect(conflicts[0].action == nil)
    }
}
