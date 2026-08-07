import Foundation

/// Prior transaction state captured when a rule was applied, so the rule can be undone later.
public struct CategorizationRuleTransactionPrior: Hashable, Sendable, Codable {
    public let transactionID: TransactionID
    public let categoryID: CategoryID
    public let userEditedCategory: Bool
    public let tagIDs: [TagID]
    public let enrichedTitle: String?
    public let enrichedLocation: String?
    public let titleSource: TitleSource?
    public let categorySource: CategorySource?

    public init(
        transactionID: TransactionID,
        categoryID: CategoryID,
        userEditedCategory: Bool,
        tagIDs: [TagID],
        enrichedTitle: String?,
        enrichedLocation: String?,
        titleSource: TitleSource?,
        categorySource: CategorySource? = nil
    ) {
        self.transactionID = transactionID
        self.categoryID = categoryID
        self.userEditedCategory = userEditedCategory
        self.tagIDs = tagIDs
        self.enrichedTitle = enrichedTitle
        self.enrichedLocation = enrichedLocation
        self.titleSource = titleSource
        self.categorySource = categorySource
    }

    private enum CodingKeys: String, CodingKey {
        case transactionID, categoryID, userEditedCategory, tagIDs
        case enrichedTitle, enrichedLocation, titleSource, categorySource
        case description // legacy — ignored on decode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try container.decode(TransactionID.self, forKey: .transactionID)
        categoryID = try container.decode(CategoryID.self, forKey: .categoryID)
        userEditedCategory = try container.decode(Bool.self, forKey: .userEditedCategory)
        tagIDs = try container.decode([TagID].self, forKey: .tagIDs)
        enrichedTitle = try container.decodeIfPresent(String.self, forKey: .enrichedTitle)
        enrichedLocation = try container.decodeIfPresent(String.self, forKey: .enrichedLocation)
        titleSource = try container.decodeIfPresent(TitleSource.self, forKey: .titleSource)
        categorySource = try container.decodeIfPresent(CategorySource.self, forKey: .categorySource)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transactionID, forKey: .transactionID)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(userEditedCategory, forKey: .userEditedCategory)
        try container.encode(tagIDs, forKey: .tagIDs)
        try container.encodeIfPresent(enrichedTitle, forKey: .enrichedTitle)
        try container.encodeIfPresent(enrichedLocation, forKey: .enrichedLocation)
        try container.encodeIfPresent(titleSource, forKey: .titleSource)
        try container.encodeIfPresent(categorySource, forKey: .categorySource)
    }
}

/// Snapshot of a rule’s last apply. Cleared after undo.
public struct CategorizationRuleApplySnapshot: Hashable, Sendable, Codable {
    public let capturedAt: Date
    public let appliesCategory: Bool
    public let categoryID: CategoryID
    public let tagIDs: [TagID]
    public let renameTitle: String?
    public let renameLocation: String?
    public let priors: [CategorizationRuleTransactionPrior]

    public init(
        capturedAt: Date = .now,
        appliesCategory: Bool,
        categoryID: CategoryID,
        tagIDs: [TagID],
        renameTitle: String?,
        renameLocation: String? = nil,
        priors: [CategorizationRuleTransactionPrior]
    ) {
        self.capturedAt = capturedAt
        self.appliesCategory = appliesCategory
        self.categoryID = categoryID
        self.tagIDs = tagIDs
        self.renameTitle = renameTitle
        self.renameLocation = renameLocation
        self.priors = priors
    }

    public var canUndo: Bool { !priors.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case capturedAt, appliesCategory, categoryID, tagIDs
        case renameTitle, renameLocation, priors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        appliesCategory = try container.decode(Bool.self, forKey: .appliesCategory)
        categoryID = try container.decode(CategoryID.self, forKey: .categoryID)
        tagIDs = try container.decode([TagID].self, forKey: .tagIDs)
        renameTitle = try container.decodeIfPresent(String.self, forKey: .renameTitle)
        renameLocation = try container.decodeIfPresent(String.self, forKey: .renameLocation)
        priors = try container.decode([CategorizationRuleTransactionPrior].self, forKey: .priors)
    }
}

/// Restorations produced by undoing a rule (manual edits already filtered out).
public struct CategorizationRuleUndoRestorations: Equatable, Sendable {
    public var categoryAssignments: [CategoryAssignment]
    public var tagAssignments: [TagAssignment]
    public var titleLocationAssignments: [TitleLocationAssignment]

    public init(
        categoryAssignments: [CategoryAssignment] = [],
        tagAssignments: [TagAssignment] = [],
        titleLocationAssignments: [TitleLocationAssignment] = []
    ) {
        self.categoryAssignments = categoryAssignments
        self.tagAssignments = tagAssignments
        self.titleLocationAssignments = titleLocationAssignments
    }

    public var isEmpty: Bool {
        categoryAssignments.isEmpty
            && tagAssignments.isEmpty
            && titleLocationAssignments.isEmpty
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
        var titles: [TitleLocationAssignment] = []

        let ruleTags = Set(snapshot.tagIDs)

        for prior in snapshot.priors {
            guard let current = currentByID[prior.transactionID] else { continue }

            if snapshot.appliesCategory {
                if current.categoryID == snapshot.categoryID {
                    categories.append(
                        CategoryAssignment(
                            transactionID: prior.transactionID,
                            categoryID: prior.categoryID,
                            userEditedCategory: prior.userEditedCategory,
                            categorySource: prior.categorySource
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

            let titleChangedByRule = snapshot.renameTitle.map {
                TransactionDescriptionMatcher.equals(current.displayTitle, other: $0)
            } ?? false
            let locationChangedByRule = snapshot.renameLocation.map { rename in
                guard let currentLocation = current.displayLocation else { return false }
                return TransactionDescriptionMatcher.equals(currentLocation, other: rename)
            } ?? false

            if (snapshot.renameTitle != nil || snapshot.renameLocation != nil),
               (titleChangedByRule || locationChangedByRule),
               current.titleSource != .user
            {
                titles.append(
                    TitleLocationAssignment(
                        transactionID: prior.transactionID,
                        title: prior.enrichedTitle,
                        location: prior.enrichedLocation,
                        titleSource: prior.titleSource
                    )
                )
            }
        }

        return CategorizationRuleUndoRestorations(
            categoryAssignments: categories,
            tagAssignments: tags,
            titleLocationAssignments: titles
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
            if let rename = rule.renameTitle,
               !TransactionDescriptionMatcher.equals(tx.displayTitle, other: rename)
            {
                wouldChange = true
            }
            if let renameLocation = rule.renameLocation {
                let current = tx.displayLocation ?? ""
                if !TransactionDescriptionMatcher.equals(current, other: renameLocation) {
                    wouldChange = true
                }
            }
            guard wouldChange else { return nil }
            return CategorizationRuleTransactionPrior(
                transactionID: tx.id,
                categoryID: tx.categoryID,
                userEditedCategory: tx.userEditedCategory,
                tagIDs: tx.tagIDs,
                enrichedTitle: tx.enrichedTitle,
                enrichedLocation: tx.enrichedLocation,
                titleSource: tx.titleSource,
                categorySource: tx.categorySource
            )
        }
    }
}
