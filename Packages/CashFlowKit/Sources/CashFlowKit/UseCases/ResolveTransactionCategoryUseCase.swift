import Foundation

public struct ResolvedCategory: Equatable, Sendable {
    public let categoryID: CategoryID
    /// True when a categorize and/or rename rule matched (not tag-only).
    public let matchedUserRule: Bool
    /// True when an enabled categorize rule matched (category should be rewritten).
    public let matchedCategoryRule: Bool
    /// Merchant title to apply when a matching rename rule exists.
    public let renameTitle: String?
    /// Location to apply when a matching location rule exists.
    public let renameLocation: String?
    /// Tags to add from all matching rules, already excluding the transaction’s suppressed set.
    public let tagIDsToAdd: [TagID]

    public init(
        categoryID: CategoryID,
        matchedUserRule: Bool,
        matchedCategoryRule: Bool = false,
        renameTitle: String? = nil,
        renameLocation: String? = nil,
        tagIDsToAdd: [TagID] = []
    ) {
        self.categoryID = categoryID
        self.matchedUserRule = matchedUserRule
        self.matchedCategoryRule = matchedCategoryRule
        self.renameTitle = renameTitle
        self.renameLocation = renameLocation
        self.tagIDsToAdd = tagIDsToAdd
    }

    public var hasRename: Bool {
        renameTitle != nil || renameLocation != nil
    }
}

/// Resolves category + rename + tags from user rules, then falls back to built-in suggestion.
///
/// Evaluation is a single pass against the transaction’s start-of-pass state: a category or
/// tag change produced here cannot cascade into another rule in the same run.
///
/// `categoryLocked` blocks category changes only — rename and tag rules still apply.
public enum ResolveTransactionCategoryUseCase: Sendable {
    public static func execute(
        transaction: Transaction,
        rules: [CategorizationRule],
        categoryLocked: Bool,
        currentCategoryID: CategoryID,
        fallbackCategoryID: CategoryID? = nil
    ) -> ResolvedCategory {
        let matchTransaction = Transaction(
            id: transaction.id,
            accountID: transaction.accountID,
            externalID: transaction.externalID,
            amount: transaction.amount,
            postedDate: transaction.postedDate,
            description: transaction.description,
            categoryID: currentCategoryID,
            currencyCode: transaction.currencyCode,
            userEditedCategory: transaction.userEditedCategory,
            isPending: transaction.isPending,
            categoryLocked: categoryLocked,
            tagIDs: transaction.tagIDs,
            suppressedTagIDs: transaction.suppressedTagIDs,
            enrichedTitle: transaction.enrichedTitle,
            enrichedLocation: transaction.enrichedLocation,
            titleSource: transaction.titleSource,
            categorySource: transaction.categorySource
        )
        let matching = CategorizationRuleMatcher.matchingRules(rules, transaction: matchTransaction)
        let categoryRule = categoryLocked ? nil : matching.first(where: \.appliesCategory)
        let renameRule = matching.first(where: { $0.renameTitle != nil || $0.renameLocation != nil })
        let tagIDsToAdd = tagsToAdd(from: matching, suppressed: transaction.suppressedTagIDs)

        if categoryRule != nil || renameRule != nil {
            let categoryID = categoryRule?.categoryID ?? currentCategoryID
            return ResolvedCategory(
                categoryID: categoryID,
                matchedUserRule: true,
                matchedCategoryRule: categoryRule != nil,
                renameTitle: renameRule?.renameTitle,
                renameLocation: renameRule?.renameLocation,
                tagIDsToAdd: tagIDsToAdd
            )
        }

        if categoryLocked {
            return ResolvedCategory(
                categoryID: currentCategoryID,
                matchedUserRule: false,
                matchedCategoryRule: false,
                renameTitle: nil,
                renameLocation: nil,
                tagIDsToAdd: tagIDsToAdd
            )
        }

        if let fallbackCategoryID {
            return ResolvedCategory(
                categoryID: fallbackCategoryID,
                matchedUserRule: false,
                matchedCategoryRule: false,
                renameTitle: nil,
                renameLocation: nil,
                tagIDsToAdd: tagIDsToAdd
            )
        }

        let suggested = SuggestTransactionCategoryUseCase.execute(
            description: transaction.displayTitle,
            amount: transaction.amount
        )
        return ResolvedCategory(
            categoryID: suggested,
            matchedUserRule: false,
            matchedCategoryRule: false,
            renameTitle: nil,
            renameLocation: nil,
            tagIDsToAdd: tagIDsToAdd
        )
    }

    /// Convenience for call sites that only have primitives (no enrichment/tags).
    public static func execute(
        description: String,
        amount: Decimal,
        accountID: AccountID,
        rules: [CategorizationRule],
        categoryLocked: Bool,
        currentCategoryID: CategoryID,
        fallbackCategoryID: CategoryID? = nil,
        tagIDs: [TagID] = [],
        suppressedTagIDs: [TagID] = [],
        enrichedTitle: String? = nil,
        enrichedLocation: String? = nil,
        titleSource: TitleSource? = nil
    ) -> ResolvedCategory {
        execute(
            transaction: Transaction(
                id: TransactionID("resolve"),
                accountID: accountID,
                externalID: "resolve",
                amount: amount,
                postedDate: .distantPast,
                description: description,
                categoryID: currentCategoryID,
                tagIDs: tagIDs,
                suppressedTagIDs: suppressedTagIDs,
                enrichedTitle: enrichedTitle,
                enrichedLocation: enrichedLocation,
                titleSource: titleSource
            ),
            rules: rules,
            categoryLocked: categoryLocked,
            currentCategoryID: currentCategoryID,
            fallbackCategoryID: fallbackCategoryID
        )
    }

    /// Unions current tags with rule tags, minus suppressions.
    public static func applyingTags(
        current: [TagID],
        ruleTags: [TagID],
        suppressed: [TagID]
    ) -> [TagID] {
        let suppressedSet = Set(suppressed)
        var ordered: [TagID] = []
        var seen = Set<TagID>()
        for tag in current + ruleTags {
            guard !suppressedSet.contains(tag), !seen.contains(tag) else { continue }
            seen.insert(tag)
            ordered.append(tag)
        }
        return ordered
    }

    /// Updates the suppression set when the user replaces tags on a row.
    /// Removed tags are suppressed; re-added tags clear their suppression.
    public static func updatedSuppressions(
        previous: [TagID],
        new: [TagID],
        existingSuppressions: [TagID]
    ) -> [TagID] {
        let previousSet = Set(previous)
        let newSet = Set(new)
        let removed = previousSet.subtracting(newSet)
        let readded = newSet
        var result = Set(existingSuppressions)
        result.formUnion(removed)
        result.subtract(readded)
        return result.sorted { $0.rawValue < $1.rawValue }
    }

    private static func tagsToAdd(
        from matching: [CategorizationRule],
        suppressed: [TagID]
    ) -> [TagID] {
        let suppressedSet = Set(suppressed)
        var ordered: [TagID] = []
        var seen = Set<TagID>()
        for rule in matching {
            for tag in rule.tagIDs where !suppressedSet.contains(tag) && !seen.contains(tag) {
                seen.insert(tag)
                ordered.append(tag)
            }
        }
        return ordered
    }
}
