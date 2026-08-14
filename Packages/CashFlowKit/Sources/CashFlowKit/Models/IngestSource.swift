import Foundation

/// Where a transaction row originally entered the local store.
public enum IngestSource: String, Hashable, Sendable, Codable {
    /// SimpleFIN or Demo sync.
    case bankLink
    /// User CSV import.
    case csvImport

    public var displayName: String {
        switch self {
        case .bankLink: return "Bank"
        case .csvImport: return "Imported"
        }
    }
}
