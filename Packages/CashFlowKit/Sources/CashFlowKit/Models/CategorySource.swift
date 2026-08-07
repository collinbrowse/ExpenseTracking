import Foundation

/// Who authored the transaction’s category.
/// Precedence: `rule` > `user` > `llm` > `keyword` (matching categorize rules may overwrite
/// unlocked user edits on re-apply / sync — same as pre-AI-first behavior). Lock is separate.
/// Lower-precedence writers must not overwrite higher via `canOverwrite`.
public enum CategorySource: String, Hashable, Sendable, Codable, Comparable {
    case keyword
    case llm
    case user
    case rule

    public var rank: Int {
        switch self {
        case .keyword: return 0
        case .llm: return 1
        case .user: return 2
        case .rule: return 3
        }
    }

    public static func < (lhs: CategorySource, rhs: CategorySource) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Whether `incoming` may replace an existing value authored by `existing`.
    public static func canOverwrite(existing: CategorySource?, with incoming: CategorySource) -> Bool {
        guard let existing else { return true }
        return incoming.rank >= existing.rank
    }

    /// Sticky for merge / `userEditedCategory` compat (`rule` and `user` only).
    public var isUserEditedCompat: Bool {
        switch self {
        case .rule, .user: return true
        case .keyword, .llm: return false
        }
    }
}
