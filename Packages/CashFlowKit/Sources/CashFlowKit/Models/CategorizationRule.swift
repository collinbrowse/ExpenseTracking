import Foundation

public struct CategorizationRuleID: Hashable, Sendable, Codable, RawRepresentable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: CategorizationRuleID, rhs: CategorizationRuleID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One filter clause. All conditions on a rule are AND’d.
public enum CategorizationCondition: Hashable, Sendable, Codable {
    case titleContains(String)
    case titleEquals(String)
    case descriptionContains(String)
    case descriptionEquals(String)
    case accountID(AccountID)
    case amountMin(Decimal)
    case amountMax(Decimal)
}

/// User-defined rule. Lower `priority` wins when multiple rules match.
///
/// - Categorize rules: `appliesCategory == true` (optional rename via `renameTitle`)
/// - Rename-only rules: `appliesCategory == false` and a non-nil `renameTitle`
public struct CategorizationRule: Identifiable, Hashable, Sendable, Codable {
    public let id: CategorizationRuleID
    public let categoryID: CategoryID
    public let priority: Int
    public let isEnabled: Bool
    public let conditions: [CategorizationCondition]
    /// When set, matching transactions get this merchant title (location preserved).
    public let renameTitle: String?
    /// When false, a matching rule only renames and leaves category unchanged.
    public let appliesCategory: Bool

    public init(
        id: CategorizationRuleID,
        categoryID: CategoryID,
        priority: Int,
        isEnabled: Bool = true,
        conditions: [CategorizationCondition],
        renameTitle: String? = nil,
        appliesCategory: Bool = true
    ) {
        self.id = id
        self.categoryID = categoryID
        self.priority = priority
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.renameTitle = Self.normalizedRename(renameTitle)
        self.appliesCategory = appliesCategory
    }

    private static func normalizedRename(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
