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
    case locationContains(String)
    case categoryIs(CategoryID)
    case hasTag(TagID)
    case accountID(AccountID)
    case amountMin(Decimal)
    case amountMax(Decimal)
}

/// User-defined rule. Lower `priority` wins when multiple rules match.
///
/// - Categorize rules: `appliesCategory == true` (optional rename via `renameTitle` / `renameLocation`)
/// - Rename-only rules: `appliesCategory == false` and a non-nil rename field
/// - Tag rules: non-empty `tagIDs` (additive; may combine with categorize/rename)
public struct CategorizationRule: Identifiable, Hashable, Sendable, Codable {
    public let id: CategorizationRuleID
    public let categoryID: CategoryID
    public let priority: Int
    public let isEnabled: Bool
    public let conditions: [CategorizationCondition]
    /// When set, matching transactions get this merchant title (enrichment, not description).
    public let renameTitle: String?
    /// When set, matching transactions get this location (enrichment, not description).
    public let renameLocation: String?
    /// When false, a matching rule only renames / tags and leaves category unchanged.
    public let appliesCategory: Bool
    /// Tags to add when the rule matches (never clears existing tags).
    public let tagIDs: [TagID]
    /// True when the assistant created this rule.
    public let createdByAssistant: Bool
    /// Prior transaction state from the last apply; enables Undo Rule.
    public let applySnapshot: CategorizationRuleApplySnapshot?

    public init(
        id: CategorizationRuleID,
        categoryID: CategoryID,
        priority: Int,
        isEnabled: Bool = true,
        conditions: [CategorizationCondition],
        renameTitle: String? = nil,
        renameLocation: String? = nil,
        appliesCategory: Bool = true,
        tagIDs: [TagID] = [],
        createdByAssistant: Bool = false,
        applySnapshot: CategorizationRuleApplySnapshot? = nil
    ) {
        self.id = id
        self.categoryID = categoryID
        self.priority = priority
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.renameTitle = Self.normalizedRename(renameTitle)
        self.renameLocation = Self.normalizedRename(renameLocation)
        self.appliesCategory = appliesCategory
        self.tagIDs = tagIDs
        self.createdByAssistant = createdByAssistant
        self.applySnapshot = applySnapshot
    }

    /// True when the rule performs at least one lasting action.
    public var hasAction: Bool {
        appliesCategory || renameTitle != nil || renameLocation != nil || !tagIDs.isEmpty
    }

    public var canUndoApply: Bool {
        applySnapshot?.canUndo == true
    }

    private enum CodingKeys: String, CodingKey {
        case id, categoryID, priority, isEnabled, conditions
        case renameTitle, renameLocation, appliesCategory, tagIDs, createdByAssistant, applySnapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CategorizationRuleID.self, forKey: .id)
        categoryID = try container.decode(CategoryID.self, forKey: .categoryID)
        priority = try container.decode(Int.self, forKey: .priority)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        conditions = try container.decode([CategorizationCondition].self, forKey: .conditions)
        renameTitle = Self.normalizedRename(try container.decodeIfPresent(String.self, forKey: .renameTitle))
        renameLocation = Self.normalizedRename(
            try container.decodeIfPresent(String.self, forKey: .renameLocation)
        )
        appliesCategory = try container.decodeIfPresent(Bool.self, forKey: .appliesCategory) ?? true
        tagIDs = try container.decodeIfPresent([TagID].self, forKey: .tagIDs) ?? []
        createdByAssistant = try container.decodeIfPresent(Bool.self, forKey: .createdByAssistant) ?? false
        applySnapshot = try container.decodeIfPresent(
            CategorizationRuleApplySnapshot.self,
            forKey: .applySnapshot
        )
    }

    private static func normalizedRename(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
