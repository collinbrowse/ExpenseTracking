import Foundation

/// One transaction’s full tag membership set.
public struct TagAssignment: Hashable, Sendable {
    public let transactionID: TransactionID
    public let tagIDs: [TagID]
    /// When non-nil, restore this exact suppression set (undo path).
    public let suppressedTagIDs: [TagID]?

    public init(
        transactionID: TransactionID,
        tagIDs: [TagID],
        suppressedTagIDs: [TagID]? = nil
    ) {
        self.transactionID = transactionID
        self.tagIDs = tagIDs
        self.suppressedTagIDs = suppressedTagIDs
    }
}

/// Prior description for undo.
public struct DescriptionAssignment: Hashable, Sendable {
    public let transactionID: TransactionID
    public let description: String

    public init(transactionID: TransactionID, description: String) {
        self.transactionID = transactionID
        self.description = description
    }
}

/// Snapshot of prior values so an applied assistant turn can be undone.
public struct AssistantUndoSnapshot: Equatable, Sendable {
    public var previousTagAssignments: [TagAssignment]
    public var previousCategoryAssignments: [CategoryAssignment]
    public var previousDescriptions: [DescriptionAssignment]
    /// Rule created or updated by this turn; undo disables it.
    public var ruleIDToDisable: CategorizationRuleID?
    public var summary: String

    public init(
        previousTagAssignments: [TagAssignment] = [],
        previousCategoryAssignments: [CategoryAssignment] = [],
        previousDescriptions: [DescriptionAssignment] = [],
        ruleIDToDisable: CategorizationRuleID? = nil,
        summary: String = ""
    ) {
        self.previousTagAssignments = previousTagAssignments
        self.previousCategoryAssignments = previousCategoryAssignments
        self.previousDescriptions = previousDescriptions
        self.ruleIDToDisable = ruleIDToDisable
        self.summary = summary
    }

    public var isEmpty: Bool {
        previousTagAssignments.isEmpty
            && previousCategoryAssignments.isEmpty
            && previousDescriptions.isEmpty
            && ruleIDToDisable == nil
    }

    public var affectedTransactionCount: Int {
        var ids = Set(previousTagAssignments.map(\.transactionID))
        ids.formUnion(previousCategoryAssignments.map(\.transactionID))
        ids.formUnion(previousDescriptions.map(\.transactionID))
        return ids.count
    }
}

public struct AssistantMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    public let id: UUID
    public let role: Role
    public let text: String

    public init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Structured intent extracted by the on-device model (no transaction rows in context).
public struct AssistantIntent: Equatable, Sendable {
    public let explanation: String
    public let conditions: [CategorizationCondition]
    public let appliesCategory: Bool
    public let categoryID: CategoryID
    public let renameTitle: String?
    public let tagNames: [String]
    public let prefersSavingRule: Bool

    public init(
        explanation: String,
        conditions: [CategorizationCondition],
        appliesCategory: Bool,
        categoryID: CategoryID,
        renameTitle: String? = nil,
        tagNames: [String] = [],
        prefersSavingRule: Bool = true
    ) {
        self.explanation = explanation
        self.conditions = conditions
        self.appliesCategory = appliesCategory
        self.categoryID = categoryID
        self.renameTitle = renameTitle
        self.tagNames = tagNames
        self.prefersSavingRule = prefersSavingRule
    }

    public var hasAction: Bool {
        appliesCategory || renameTitle != nil || !tagNames.isEmpty
    }
}

public struct AssistantProposalSample: Identifiable, Equatable, Sendable {
    public let id: TransactionID
    public let title: String
    public let detail: String

    public init(id: TransactionID, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// Preview shown before the user taps Run. Nothing is persisted until execute.
public struct AssistantProposal: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let summary: String
    public let conditionSummary: String
    public let affectedCount: Int
    public let samples: [AssistantProposalSample]
    public var saveAsRule: Bool
    public let warnings: [String]
    public let conditions: [CategorizationCondition]
    public let appliesCategory: Bool
    public let categoryID: CategoryID
    public let renameTitle: String?
    /// Tag names from intent; created during execute so interpret stays read-only.
    public let tagNames: [String]
    public let matchingTransactionIDs: [TransactionID]

    public init(
        id: UUID = UUID(),
        summary: String,
        conditionSummary: String,
        affectedCount: Int,
        samples: [AssistantProposalSample],
        saveAsRule: Bool,
        warnings: [String] = [],
        conditions: [CategorizationCondition],
        appliesCategory: Bool,
        categoryID: CategoryID,
        renameTitle: String? = nil,
        tagNames: [String] = [],
        matchingTransactionIDs: [TransactionID]
    ) {
        self.id = id
        self.summary = summary
        self.conditionSummary = conditionSummary
        self.affectedCount = affectedCount
        self.samples = samples
        self.saveAsRule = saveAsRule
        self.warnings = warnings
        self.conditions = conditions
        self.appliesCategory = appliesCategory
        self.categoryID = categoryID
        self.renameTitle = renameTitle
        self.tagNames = tagNames
        self.matchingTransactionIDs = matchingTransactionIDs
    }

    public var isLargeSet: Bool { affectedCount > 200 }
}

public struct AssistantTurn: Equatable, Sendable {
    public let message: AssistantMessage
    public let undoSnapshot: AssistantUndoSnapshot?

    public init(message: AssistantMessage, undoSnapshot: AssistantUndoSnapshot? = nil) {
        self.message = message
        self.undoSnapshot = undoSnapshot
    }
}
