import Foundation

/// Domain merge policy: remote wins amount/date/description; lock / rules / user edit / LLM
/// gate category; matching rename rules update enrichment (never bank description); rule tags
/// are additive and honor per-tag suppressions.
///
/// New rows start as Undefined until enrichment (LLM, then keyword fallback), unless
/// `preferSuggestedCategory` (Demo fixtures) stamps remote’s suggested category as `.keyword`.
/// Pending remotes skip user rules. Rules apply when the row posts.
public enum MergeSyncPolicy: Sendable {
    public static func merge(
        local: Transaction?,
        remote: Transaction,
        rules: [CategorizationRule] = [],
        preferSuggestedCategory: Bool = false
    ) -> Transaction {
        let effectiveRules = remote.isPending ? [] : rules

        guard let local else {
            let resolved = ResolveTransactionCategoryUseCase.execute(
                transaction: remote,
                rules: effectiveRules,
                categoryLocked: false,
                currentCategoryID: SystemCategory.undefined.id,
                fallbackCategoryID: SystemCategory.undefined.id
            )
            let (title, location, source) = appliedEnrichment(
                existingTitle: nil,
                existingLocation: nil,
                existingSource: nil,
                resolved: resolved,
                fallbackTitle: nil
            )
            let categoryID: CategoryID
            let categorySource: CategorySource?
            if resolved.matchedCategoryRule {
                categoryID = resolved.categoryID
                categorySource = .rule
            } else if preferSuggestedCategory,
                      remote.categoryID != SystemCategory.undefined.id
            {
                categoryID = remote.categoryID
                categorySource = .keyword
            } else {
                categoryID = SystemCategory.undefined.id
                categorySource = nil
            }
            return Transaction(
                id: remote.id,
                accountID: remote.accountID,
                externalID: remote.externalID,
                amount: remote.amount,
                postedDate: remote.postedDate,
                description: remote.description,
                categoryID: categoryID,
                currencyCode: remote.currencyCode,
                userEditedCategory: categorySource?.isUserEditedCompat ?? false,
                isPending: remote.isPending,
                categoryLocked: false,
                tagIDs: ResolveTransactionCategoryUseCase.applyingTags(
                    current: [],
                    ruleTags: resolved.tagIDsToAdd,
                    suppressed: []
                ),
                suppressedTagIDs: [],
                enrichedTitle: title,
                enrichedLocation: location,
                titleSource: source,
                categorySource: categorySource
            )
        }

        // Bank description is immutable after ingest — always take remote's raw text.
        // If the bank string changes, clear enrichment so it can be refilled.
        let descriptionChanged = local.description != remote.description

        let locked = local.categoryLocked
        let matchBase = Transaction(
            id: local.id,
            accountID: remote.accountID,
            externalID: remote.externalID,
            amount: remote.amount,
            postedDate: remote.postedDate,
            description: remote.description,
            categoryID: local.categoryID,
            currencyCode: remote.currencyCode,
            userEditedCategory: local.userEditedCategory,
            isPending: remote.isPending,
            categoryLocked: locked,
            tagIDs: local.tagIDs,
            suppressedTagIDs: local.suppressedTagIDs,
            enrichedTitle: descriptionChanged ? nil : local.enrichedTitle,
            enrichedLocation: descriptionChanged ? nil : local.enrichedLocation,
            titleSource: descriptionChanged ? nil : local.titleSource,
            categorySource: local.categorySource
        )

        let resolved: ResolvedCategory
        let categoryID: CategoryID
        let categorySource: CategorySource?
        let userEdited: Bool

        if locked {
            resolved = ResolveTransactionCategoryUseCase.execute(
                transaction: matchBase,
                rules: effectiveRules,
                categoryLocked: true,
                currentCategoryID: local.categoryID,
                fallbackCategoryID: SystemCategory.undefined.id
            )
            categoryID = local.categoryID
            categorySource = local.categorySource
            userEdited = local.userEditedCategory
        } else {
            resolved = ResolveTransactionCategoryUseCase.execute(
                transaction: matchBase,
                rules: effectiveRules,
                categoryLocked: false,
                currentCategoryID: local.categoryID,
                fallbackCategoryID: SystemCategory.undefined.id
            )
            if resolved.matchedCategoryRule {
                categoryID = resolved.categoryID
                categorySource = .rule
                userEdited = true
            } else if isUserSticky(local) {
                // User edit always wins — including across bank description changes.
                categoryID = local.categoryID
                categorySource = local.categorySource == .user ? .user : (local.categorySource ?? .user)
                userEdited = true
            } else if remote.isPending {
                // Pending stays unprocessed until posted (LLM / keyword run after post).
                categoryID = SystemCategory.undefined.id
                categorySource = nil
                userEdited = false
            } else if descriptionChanged {
                categoryID = SystemCategory.undefined.id
                categorySource = nil
                userEdited = false
            } else if isProcessedSticky(local) {
                categoryID = local.categoryID
                categorySource = effectiveProcessedSource(local)
                userEdited = false
            } else {
                // Still Undefined / unprocessed — stay on Undefined until enrichment.
                categoryID = SystemCategory.undefined.id
                categorySource = nil
                userEdited = false
            }
        }

        let existingTitle = descriptionChanged ? nil : local.enrichedTitle
        let existingLocation = descriptionChanged ? nil : local.enrichedLocation
        let existingSource = descriptionChanged ? nil : local.titleSource
        let (title, location, source) = appliedEnrichment(
            existingTitle: existingTitle,
            existingLocation: existingLocation,
            existingSource: existingSource,
            resolved: resolved,
            fallbackTitle: existingTitle
        )

        let tagIDs = ResolveTransactionCategoryUseCase.applyingTags(
            current: local.tagIDs,
            ruleTags: resolved.tagIDsToAdd,
            suppressed: local.suppressedTagIDs
        )
        return Transaction(
            id: local.id,
            accountID: remote.accountID,
            externalID: remote.externalID,
            amount: remote.amount,
            postedDate: resolvedPostedDate(local: local, remote: remote),
            description: remote.description,
            categoryID: categoryID,
            currencyCode: remote.currencyCode,
            userEditedCategory: userEdited,
            isPending: remote.isPending,
            categoryLocked: locked,
            tagIDs: tagIDs,
            suppressedTagIDs: local.suppressedTagIDs,
            enrichedTitle: title,
            enrichedLocation: location,
            titleSource: source,
            categorySource: categorySource
        )
    }

    /// While still pending, keep the earlier date so sync-time stand-ins for `posted == 0` do not churn.
    private static func resolvedPostedDate(local: Transaction, remote: Transaction) -> Date {
        if remote.isPending && local.isPending {
            return min(local.postedDate, remote.postedDate)
        }
        return remote.postedDate
    }

    private static func isUserSticky(_ local: Transaction) -> Bool {
        if local.categorySource == .user { return true }
        if local.userEditedCategory, local.categorySource != .rule, local.categorySource != .llm,
           local.categorySource != .keyword
        {
            return true
        }
        // Compat: sticky bool without source, and not a rule-stamped row we can tell apart.
        if local.userEditedCategory, local.categorySource == nil {
            return true
        }
        return false
    }

    private static func isProcessedSticky(_ local: Transaction) -> Bool {
        if local.categorySource == .llm || local.categorySource == .keyword { return true }
        if local.categorySource == .rule { return true }
        // Legacy row with a real category and no Undefined marker.
        if local.categoryID != SystemCategory.undefined.id,
           local.categorySource == nil,
           !local.userEditedCategory
        {
            return true
        }
        return false
    }

    private static func effectiveProcessedSource(_ local: Transaction) -> CategorySource? {
        if let source = local.categorySource { return source }
        if local.categoryID != SystemCategory.undefined.id { return .keyword }
        return nil
    }

    private static func appliedEnrichment(
        existingTitle: String?,
        existingLocation: String?,
        existingSource: TitleSource?,
        resolved: ResolvedCategory,
        fallbackTitle: String?
    ) -> (String?, String?, TitleSource?) {
        guard resolved.hasRename else {
            return (existingTitle, existingLocation, existingSource)
        }
        // User-authored enrichment must not be clobbered by a rule during sync.
        if existingSource == .user {
            return (existingTitle, existingLocation, existingSource)
        }
        let title = resolved.renameTitle ?? existingTitle ?? fallbackTitle
        let location = resolved.renameLocation ?? existingLocation
        guard let title, !title.isEmpty else {
            return (existingTitle, existingLocation, existingSource)
        }
        return (title, location, .rule)
    }
}
