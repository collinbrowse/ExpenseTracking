import Foundation

public struct TagID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// User-defined label orthogonal to system categories (e.g. “Japan Trip”).
public struct Tag: Identifiable, Hashable, Sendable, Codable {
    public let id: TagID
    public let name: String
    public let createdAt: Date

    public init(id: TagID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
