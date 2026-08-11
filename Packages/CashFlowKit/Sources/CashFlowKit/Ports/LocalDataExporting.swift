import Foundation

/// Filtered transaction CSV export. Omits Keychain credentials.
public protocol LocalDataExporting: Sendable {
    /// UTF-8 CSV of transactions matching `filter` (same semantics as the Transactions list).
    func exportCSV(filter: TransactionFilter) async throws -> Data
}
