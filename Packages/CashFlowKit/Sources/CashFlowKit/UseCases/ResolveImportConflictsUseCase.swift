import Foundation

/// Applies per-row and bulk conflict decisions before commit.
public struct ResolveImportConflictsUseCase: Sendable {
    public init() {}

    public func applyBulk(
        _ action: ImportConflictAction,
        to conflicts: inout [CSVImportConflict]
    ) {
        for index in conflicts.indices {
            conflicts[index].action = action
        }
    }

    public func setAction(
        _ action: ImportConflictAction?,
        forConflictID id: String,
        in conflicts: inout [CSVImportConflict]
    ) {
        guard let index = conflicts.firstIndex(where: { $0.id == id }) else { return }
        conflicts[index].action = action
    }

    public func allResolved(_ conflicts: [CSVImportConflict]) -> Bool {
        conflicts.allSatisfy { $0.action != nil }
    }

    /// Rows that should be inserted as new (no conflict, or keepBoth).
    public func rowsToInsert(
        allValidRows: [CSVImportRow],
        conflicts: [CSVImportConflict]
    ) -> [CSVImportRow] {
        let conflictedIDs = Set(conflicts.map(\.importRow.id))
        let keepBoth = conflicts.filter { $0.action == .keepBoth }.map(\.importRow)
        let nonConflicted = allValidRows.filter { !conflictedIDs.contains($0.id) }
        return nonConflicted + keepBoth
    }

    /// Rows that replace an existing transaction.
    public func replacements(conflicts: [CSVImportConflict]) -> [(row: CSVImportRow, existingID: TransactionID)] {
        conflicts
            .filter { $0.action == .replace }
            .map { ($0.importRow, $0.existingTransactionID) }
    }

    public func skippedCount(conflicts: [CSVImportConflict]) -> Int {
        conflicts.filter { $0.action == .skip }.count
    }
}

/// Builds conflict list by fingerprint against existing transactions on the target account.
public struct MatchImportFingerprintsUseCase: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func execute(
        rows: [CSVImportRow],
        accountID: AccountID,
        existing: [Transaction]
    ) -> [CSVImportConflict] {
        var byFingerprint: [TransactionFingerprint: Transaction] = [:]
        byFingerprint.reserveCapacity(existing.count)
        for tx in existing where tx.accountID == accountID {
            let fp = TransactionFingerprint(
                accountID: accountID,
                postedDate: tx.postedDate,
                amount: tx.amount,
                description: tx.description,
                calendar: calendar
            )
            if byFingerprint[fp] == nil {
                byFingerprint[fp] = tx
            }
        }

        var conflicts: [CSVImportConflict] = []
        for row in rows where row.isValid {
            let fp = TransactionFingerprint(
                accountID: accountID,
                postedDate: row.postedDate,
                amount: row.amount,
                description: row.description,
                calendar: calendar
            )
            guard let match = byFingerprint[fp] else { continue }
            conflicts.append(
                CSVImportConflict(
                    importRow: row,
                    existingTransactionID: match.id,
                    existingDescription: match.displayTitle,
                    existingAmount: match.amount,
                    existingPostedDate: match.postedDate,
                    action: nil
                )
            )
        }
        return conflicts
    }
}
