import Foundation

/// Prior transaction state captured when a rule was applied, so the rule can be undone later.
public struct CategorizationRuleTransactionPrior: Hashable, Sendable, Codable {
    public let transactionID: TransactionID
    public let categoryID: CategoryID
    public let userEditedCategory: Bool
    public let tagIDs: [TagID]
    public let description: String

    public init(
        transactionID: TransactionID,
        categoryID: CategoryID,
        userEditedCategory: Bool,
        tagIDs: [TagID],
        description: String
    ) {
        self.transactionID = transactionID
        self.categoryID = categoryID
        self.userEditedCategory = userEditedCategory
        self.tagIDs = tagIDs
        self.description = description
    }
}

/// Snapshot of a rule’s last apply. Cleared after undo.
public struct CategorizationRuleApplySnapshot: Hashable, Sendable, Codable {
    public let capturedAt: Date
    public let appliesCategory: Bool
    public let categoryID: CategoryID
    public let tagIDs: [TagID]
    public let renameTitle: String?
    public let priors: [CategorizationRuleTransactionPrior]

    public init(
        capturedAt: Date = .now,
        appliesCategory: Bool,
        categoryID: CategoryID,
        tagIDs: [TagID],
        renameTitle: String?,
        priors: [CategorizationRuleTransactionPrior]
    ) {
        self.capturedAt = capturedAt
        self.appliesCategory = appliesCategory
        self.categoryID = categoryID
        self.tagIDs = tagIDs
        self.renameTitle = renameTitle
        self.priors = priors
    }

    public var canUndo: Bool { !priors.isEmpty }
}

/// Restorations produced by undoing a rule (manual edits already filtered out).
public struct CategorizationRuleUndoRestorations: Equatable, Sendable {
    public var categoryAssignments: [CategoryAssignment]
    public var tagAssignments: [TagAssignment]
    public var descriptionAssignments: [DescriptionAssignment]

    public init(
        categoryAssignments: [CategoryAssignment] = [],
        tagAssignments: [TagAssignment] = [],
        descriptionAssignments: [DescriptionAssignment] = []
    ) {
        self.categoryAssignments = categoryAssignments
        self.tagAssignments = tagAssignments
        self.descriptionAssignments = descriptionAssignments
    }

    public var isEmpty: Bool {
        categoryAssignments.isEmpty && tagAssignments.isEmpty && descriptionAssignments.isEmpty
    }
}

/// Builds undo restorations where later manual edits win over the rule’s effect.
public enum UndoCategorizationRuleUseCase: Sendable {
    public static func restorations(
        snapshot: CategorizationRuleApplySnapshot,
        currentByID: [TransactionID: Transaction]
    ) -> CategorizationRuleUndoRestorations {
        var categories: [CategoryAssignment] = []
        var tags: [TagAssignment] = []
        var descriptions: [DescriptionAssignment] = []

        let ruleTags = Set(snapshot.tagIDs)

        for prior in snapshot.priors {
            guard let current = currentByID[prior.transactionID] else { continue }

            if snapshot.appliesCategory {
                // Restore only while the rule’s category is still present.
                if current.categoryID == snapshot.categoryID {
                    categories.append(
                        CategoryAssignment(
                            transactionID: prior.transactionID,
                            categoryID: prior.categoryID,
                            userEditedCategory: prior.userEditedCategory
                        )
                    )
                }
            }

            let priorTags = Set(prior.tagIDs)
            let ruleAdded = ruleTags.subtracting(priorTags)
            if !ruleAdded.isEmpty {
                let restored = current.tagIDs.filter { !ruleAdded.contains($0) }
                if Set(restored) != Set(current.tagIDs) {
                    tags.append(
                        TagAssignment(
                            transactionID: prior.transactionID,
                            tagIDs: restored,
                            suppressedTagIDs: current.suppressedTagIDs
                        )
                    )
                }
            }

            if let renameTitle = snapshot.renameTitle {
                let renamed = ResolveTransactionCategoryUseCase.applyingRename(
                    to: prior.description,
                    renameTitle: renameTitle
                )
                // Restore only if the user hasn’t manually changed the title since.
                if current.description == renamed
                    || TransactionDescriptionMatcher.equals(current.displayTitle, other: renameTitle)
                {
                    descriptions.append(
                        DescriptionAssignment(
                            transactionID: prior.transactionID,
                            description: prior.description
                        )
                    )
                }
            }
        }

        return CategorizationRuleUndoRestorations(
            categoryAssignments: categories,
            tagAssignments: tags,
            descriptionAssignments: descriptions
        )
    }

    /// Priors for transactions this rule would change from their current state.
    public static func priorsToCapture(
        rule: CategorizationRule,
        matching: [Transaction]
    ) -> [CategorizationRuleTransactionPrior] {
        matching.compactMap { tx -> CategorizationRuleTransactionPrior? in
            var wouldChange = false
            if rule.appliesCategory, !tx.categoryLocked, tx.categoryID != rule.categoryID {
                wouldChange = true
            }
            let ruleAdded = Set(rule.tagIDs).subtracting(tx.tagIDs).subtracting(tx.suppressedTagIDs)
            if !ruleAdded.isEmpty { wouldChange = true }
            if let rename = rule.renameTitle {
                let renamed = ResolveTransactionCategoryUseCase.applyingRename(
                    to: tx.description,
                    renameTitle: rename
                )
                if renamed != tx.description { wouldChange = true }
            }
            guard wouldChange else { return nil }
            return CategorizationRuleTransactionPrior(
                transactionID: tx.id,
                categoryID: tx.categoryID,
                userEditedCategory: tx.userEditedCategory,
                tagIDs: tx.tagIDs,
                description: tx.description
            )
        }
    }
}
