import Foundation

/// Full local ledger snapshot as UTF-8 JSON. Not for list UI.
/// Omits Keychain credentials and regenerable LLM memo cache.
public protocol LocalDataExporting: Sendable {
    func exportJSON() async throws -> Data
}
