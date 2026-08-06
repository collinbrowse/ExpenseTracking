import Foundation

/// Who authored the local `enrichedTitle` / `enrichedLocation` cache.
/// Precedence: `user` > `rule` > `llm` > `skipped`. Lower-precedence writers must not overwrite higher.
/// `skipped` means on-device cleanup tried and left the row on raw bank text (no `enrichedTitle`).
public enum TitleSource: String, Hashable, Sendable, Codable, Comparable {
    case skipped
    case llm
    case rule
    case user

    public var rank: Int {
        switch self {
        case .skipped: return -1
        case .llm: return 0
        case .rule: return 1
        case .user: return 2
        }
    }

    public static func < (lhs: TitleSource, rhs: TitleSource) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Whether `incoming` may replace an existing value authored by `existing`.
    public static func canOverwrite(existing: TitleSource?, with incoming: TitleSource) -> Bool {
        guard let existing else { return true }
        return incoming.rank >= existing.rank
    }
}
