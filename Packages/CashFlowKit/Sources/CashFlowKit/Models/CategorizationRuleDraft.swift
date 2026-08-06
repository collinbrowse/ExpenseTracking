import Foundation

/// Structured draft that fills the same fields as the manual rule editor.
public struct CategorizationRuleDraft: Equatable, Sendable {
    public enum Action: String, Sendable, Equatable {
        case categorize
        case rename
    }

    public let action: Action
    public let categoryID: CategoryID
    public let renameTitle: String?
    public let renameLocation: String?
    public let conditions: [CategorizationCondition]
    public let explanation: String

    public init(
        action: Action,
        categoryID: CategoryID,
        renameTitle: String? = nil,
        renameLocation: String? = nil,
        conditions: [CategorizationCondition],
        explanation: String = ""
    ) {
        self.action = action
        self.categoryID = categoryID
        self.renameTitle = renameTitle
        self.renameLocation = renameLocation
        self.conditions = conditions
        self.explanation = explanation
    }

    /// Builds the same `CategorizationRule` shape the editor saves.
    public func makeRule(
        id: CategorizationRuleID = CategorizationRuleID(UUID().uuidString),
        priority: Int,
        isEnabled: Bool = true
    ) -> CategorizationRule {
        switch action {
        case .categorize:
            return CategorizationRule(
                id: id,
                categoryID: categoryID,
                priority: priority,
                isEnabled: isEnabled,
                conditions: conditions,
                renameTitle: nil,
                renameLocation: nil,
                appliesCategory: true,
                tagIDs: [],
                createdByAssistant: false
            )
        case .rename:
            return CategorizationRule(
                id: id,
                categoryID: categoryID,
                priority: priority,
                isEnabled: isEnabled,
                conditions: conditions,
                renameTitle: renameTitle,
                renameLocation: renameLocation,
                appliesCategory: false,
                tagIDs: [],
                createdByAssistant: false
            )
        }
    }
}
