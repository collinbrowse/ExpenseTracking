import Foundation

/// Domain merge policy: remote wins amount/date/description; lock / user rules / user edit gate
/// category; matching rename rules update enrichment (never bank description); rule tags are
/// additive and honor per-tag suppressions.
///
/// Pending remotes skip user rules (same as re-apply / assistant). Rules apply when the row posts.
public enum MergeSyncPolicy: Sendable {
    public static func merge(
        local: Transaction?,
        remote: Transaction,
        rules: [CategorizationRule] = []
    ) -> Transaction {
        let effectiveRules = remote.isPending ? [] : rules

        guard let local else {
            let resolved = ResolveTransactionCategoryUseCase.execute(
                transaction: remote,
                rules: effectiveRules,
                categoryLocked: false,
                currentCategoryID: remote.categoryID,
                fallbackCategoryID: remote.categoryID
            )
            let (title, location, source) = appliedEnrichment(
                existingTitle: nil,
                existingLocation: nil,
                existingSource: nil,
                resolved: resolved,
                fallbackTitle: nil
            )
            return Transaction(
                id: remote.id,
                accountID: remote.accountID,
                externalID: remote.externalID,
                amount: remote.amount,
                postedDate: remote.postedDate,
                description: remote.description,
                categoryID: resolved.categoryID,
                currencyCode: remote.currencyCode,
                userEditedCategory: resolved.matchedUserRule,
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
                titleSource: source
            )
        }

        // Bank description is immutable after ingest — always take remote's raw text.
        // If the bank string changes, clear enrichment so it can be refilled.
        let descriptionChanged = local.description != remote.description

        let categoryID: CategoryID
        let userEdited: Bool
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
            titleSource: descriptionChanged ? nil : local.titleSource
        )

        let resolved: ResolvedCategory
        if locked {
            resolved = ResolveTransactionCategoryUseCase.execute(
                transaction: matchBase,
                rules: effectiveRules,
                categoryLocked: true,
                currentCategoryID: local.categoryID,
                fallbackCategoryID: remote.categoryID
            )
            categoryID = local.categoryID
            userEdited = local.userEditedCategory
        } else {
            resolved = ResolveTransactionCategoryUseCase.execute(
                transaction: matchBase,
                rules: effectiveRules,
                categoryLocked: false,
                currentCategoryID: local.categoryID,
                fallbackCategoryID: remote.categoryID
            )
            if resolved.matchedUserRule {
                categoryID = resolved.categoryID
                userEdited = true
            } else if local.userEditedCategory {
                categoryID = local.categoryID
                userEdited = true
            } else {
                categoryID = remote.categoryID
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
            titleSource: source
        )
    }

    /// While still pending, keep the earlier date so sync-time stand-ins for `posted == 0` do not churn.
    private static func resolvedPostedDate(local: Transaction, remote: Transaction) -> Date {
        if remote.isPending && local.isPending {
            return min(local.postedDate, remote.postedDate)
        }
        return remote.postedDate
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
