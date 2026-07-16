import Foundation

/// Domain merge policy: remote wins amount/date/description; local wins category when user edited.
public enum MergeSyncPolicy: Sendable {
    public static func merge(local: Transaction?, remote: Transaction) -> Transaction {
        guard let local else { return remote }

        let categoryID: CategoryID
        let userEdited: Bool
        if local.userEditedCategory {
            categoryID = local.categoryID
            userEdited = true
        } else {
            categoryID = remote.categoryID
            userEdited = false
        }

        return Transaction(
            id: local.id,
            accountID: remote.accountID,
            externalID: remote.externalID,
            amount: remote.amount,
            postedDate: remote.postedDate,
            description: remote.description,
            categoryID: categoryID,
            currencyCode: remote.currencyCode,
            userEditedCategory: userEdited,
            isPending: remote.isPending
        )
    }
}
