import Foundation

/// CSV import preview, commit, and batch history (Settings → Data).
public protocol CSVImporting: Sendable {
    /// Parses headers/rows; pass `mapping` to override auto-detect (nil = detect).
    func parsePreview(data: Data, fileName: String, mapping: CSVColumnMapping?) async throws -> CSVImportPreview

    /// Fingerprint conflicts for valid rows against the chosen account.
    func findConflicts(
        rows: [CSVImportRow],
        accountID: AccountID
    ) async throws -> [CSVImportConflict]

    /// Inserts/replaces per plan, records an import batch, then triggers enrichment.
    func commit(_ plan: CSVImportCommitPlan) async throws -> CSVImportCommitResult

    func listBatches() async throws -> [ImportBatch]

    /// Deletes transactions from this batch; orphans a created account when empty; tombstones the batch.
    func deleteBatch(id: ImportBatchID) async throws -> ImportBatch
}
