import Foundation

/// Merchant title + optional location from bank description enrichment or user/rule authorship.
public struct ParsedTransactionDescription: Equatable, Sendable {
    public let title: String
    public let location: String?
    public let raw: String

    public init(title: String, location: String?, raw: String) {
        self.title = title
        self.location = location
        self.raw = raw
    }
}
