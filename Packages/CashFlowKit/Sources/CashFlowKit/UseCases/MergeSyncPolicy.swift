import Foundation

/// Domain merge policy: remote wins amount/date; lock / user rules / user edit gate category;
/// matching rename rules override description; sticky category also keeps a prior local title;
/// rule tags are additive and honor per-tag suppressions.
///
/// Pending remotes skip user rules (same as re-apply / assistant). Rules apply when the row posts.
public enum MergeSyncPolicy: Sendable {
    public static func merge(
        local: Transaction?,
        remote: Transaction,
        rules: [CategorizationRule] = []
    ) -> Transaction {
        // Align with CategorizationRuleReapplier / fetchAllForCategorization: pending is out of scope.
        let effectiveRules = remote.isPending ? [] : rules

        guard let local else {
            let resolved = ResolveTransactionCategoryUseCase.execute(
                transaction: remote,
                rules: effectiveRules,
                categoryLocked: false,
                currentCategoryID: remote.categoryID,
                fallbackCategoryID: remote.categoryID
            )
            let description = renamedDescription(
                from: remote.description,
                renameTitle: resolved.renameTitle
            )
            return Transaction(
                id: remote.id,
                accountID: remote.accountID,
                externalID: remote.externalID,
                amount: remote.amount,
                postedDate: remote.postedDate,
                description: description,
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
                enrichedTitle: nil,
                enrichedLocation: nil
            )
        }

        let categoryID: CategoryID
        let userEdited: Bool
        let locked = local.categoryLocked
        let description: String
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
            enrichedTitle: local.enrichedTitle,
            enrichedLocation: local.enrichedLocation
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
            // Lock blocks category only — rename rules still rewrite the title.
            if let renameTitle = resolved.renameTitle {
                description = renamedDescription(
                    from: remote.description,
                    renameTitle: renameTitle
                )
            } else {
                description = local.description
            }
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
                if resolved.renameTitle != nil {
                    description = renamedDescription(
                        from: remote.description,
                        renameTitle: resolved.renameTitle
                    )
                } else if local.userEditedCategory {
                    // Categorize-only match must not wipe a prior rename/manual title.
                    description = local.description
                } else {
                    description = remote.description
                }
            } else if local.userEditedCategory {
                categoryID = local.categoryID
                userEdited = true
                // Keep rule/manual title across sync when category is sticky.
                description = local.description
            } else {
                categoryID = remote.categoryID
                userEdited = false
                description = remote.description
            }
        }

        // Keep enrichment only when the stored description is unchanged.
        let keepEnrichment = description == local.description
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
            description: description,
            categoryID: categoryID,
            currencyCode: remote.currencyCode,
            userEditedCategory: userEdited,
            isPending: remote.isPending,
            categoryLocked: locked,
            tagIDs: tagIDs,
            suppressedTagIDs: local.suppressedTagIDs,
            enrichedTitle: keepEnrichment ? local.enrichedTitle : nil,
            enrichedLocation: keepEnrichment ? local.enrichedLocation : nil
        )
    }

    /// While still pending, keep the earlier date so sync-time stand-ins for `posted == 0` do not churn.
    private static func resolvedPostedDate(local: Transaction, remote: Transaction) -> Date {
        if remote.isPending && local.isPending {
            return min(local.postedDate, remote.postedDate)
        }
        return remote.postedDate
    }

    private static func renamedDescription(from description: String, renameTitle: String?) -> String {
        guard let renameTitle else { return description }
        return ResolveTransactionCategoryUseCase.applyingRename(
            to: description,
            renameTitle: renameTitle
        )
    }
}
