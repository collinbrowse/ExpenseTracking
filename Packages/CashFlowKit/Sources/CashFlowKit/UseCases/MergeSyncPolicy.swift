import Foundation

/// Domain merge policy: remote wins amount/date; lock / user rules / user edit gate category;
/// matching rename rules override description; sticky category also keeps a prior local title.
public enum MergeSyncPolicy: Sendable {
    public static func merge(
        local: Transaction?,
        remote: Transaction,
        rules: [CategorizationRule] = []
    ) -> Transaction {
        guard let local else {
            let resolved = ResolveTransactionCategoryUseCase.execute(
                description: remote.description,
                amount: remote.amount,
                accountID: remote.accountID,
                rules: rules,
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
                categoryLocked: false
            )
        }

        let categoryID: CategoryID
        let userEdited: Bool
        let locked = local.categoryLocked
        let description: String

        if locked {
            categoryID = local.categoryID
            userEdited = local.userEditedCategory
            // Lock blocks category only — rename rules still rewrite the title.
            let resolved = ResolveTransactionCategoryUseCase.execute(
                description: remote.description,
                amount: remote.amount,
                accountID: remote.accountID,
                rules: rules,
                categoryLocked: true,
                currentCategoryID: local.categoryID,
                fallbackCategoryID: remote.categoryID
            )
            if let renameTitle = resolved.renameTitle {
                description = renamedDescription(
                    from: remote.description,
                    renameTitle: renameTitle
                )
            } else {
                description = local.description
            }
        } else {
            let resolved = ResolveTransactionCategoryUseCase.execute(
                description: remote.description,
                amount: remote.amount,
                accountID: remote.accountID,
                rules: rules,
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
            categoryLocked: locked
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
