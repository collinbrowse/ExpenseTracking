import Foundation
import SwiftData
import CashFlowKit

enum SyncMergeEngine {
    static func merge(
        payload: RemoteSyncPayload,
        into context: ModelContext
    ) throws {
        let rules = try loadRules(from: context)
        for remoteAccount in payload.accounts {
            let account = try upsertAccount(remoteAccount, context: context)
            var remoteExternalIDs = Set<String>()
            remoteExternalIDs.reserveCapacity(remoteAccount.transactions.count)
            for remoteTx in remoteAccount.transactions {
                remoteExternalIDs.insert(remoteTx.externalID)
                try upsertTransaction(
                    remoteTx,
                    account: account,
                    rules: rules,
                    context: context
                )
            }
            // With pending=1, the payload's pending set is authoritative for this account.
            // Drop local pendings that vanished (posted under a new id, or cancelled).
            try removeStalePendingTransactions(
                account: account,
                remoteExternalIDs: remoteExternalIDs,
                context: context
            )
        }
        try context.save()
    }

    private static func loadRules(from context: ModelContext) throws -> [CategorizationRule] {
        let descriptor = FetchDescriptor<CategorizationRuleEntity>(
            sortBy: [
                SortDescriptor(\.priority, order: .forward),
                SortDescriptor(\.id, order: .forward),
            ]
        )
        return try context.fetch(descriptor).map { try EntityMappers.categorizationRule(from: $0) }
    }

    private static func upsertAccount(
        _ remote: RemoteAccountSnapshot,
        context: ModelContext
    ) throws -> AccountEntity {
        let externalID = remote.externalID
        let predicate = #Predicate<AccountEntity> { $0.externalID == externalID }
        var descriptor = FetchDescriptor<AccountEntity>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            let resolved = MergeAccountSyncPolicy.resolvedName(
                localName: existing.name,
                localUserEditedName: existing.userEditedName,
                remoteName: remote.name
            )
            existing.name = resolved.name
            existing.userEditedName = resolved.userEditedName
            existing.institutionName = remote.institutionName
            existing.currencyCode = remote.currencyCode
            existing.balance = remote.balance
            existing.balanceDate = remote.balanceDate
            existing.connectionExternalID = remote.connectionExternalID
            existing.syncIssue = remote.syncIssue
            return existing
        }

        let entity = AccountEntity(
            id: UUID().uuidString,
            externalID: remote.externalID,
            name: remote.name,
            institutionName: remote.institutionName,
            currencyCode: remote.currencyCode,
            balance: remote.balance,
            balanceDate: remote.balanceDate,
            userEditedName: false,
            connectionExternalID: remote.connectionExternalID,
            syncIssue: remote.syncIssue
        )
        context.insert(entity)
        return entity
    }

    private static func upsertTransaction(
        _ remote: RemoteTransactionSnapshot,
        account: AccountEntity,
        rules: [CategorizationRule],
        context: ModelContext
    ) throws {
        let syncKey = "\(account.externalID)|\(remote.externalID)"
        let predicate = #Predicate<TransactionEntity> { $0.syncKey == syncKey }
        var descriptor = FetchDescriptor<TransactionEntity>(predicate: predicate)
        descriptor.fetchLimit = 1

        let remoteDomain = Transaction(
            id: TransactionID(syncKey),
            accountID: AccountID(account.id),
            externalID: remote.externalID,
            amount: remote.amount,
            postedDate: remote.postedDate,
            description: remote.description,
            categoryID: remote.suggestedCategoryID,
            currencyCode: account.currencyCode,
            userEditedCategory: false,
            isPending: remote.isPending,
            categoryLocked: false
        )

        if let existing = try context.fetch(descriptor).first {
            let local = EntityMappers.transaction(from: existing)
            let merged = MergeSyncPolicy.merge(local: local, remote: remoteDomain, rules: rules)
            existing.amount = merged.amount
            existing.postedDate = merged.postedDate
            existing.transactionDescription = merged.description
            existing.categoryID = merged.categoryID.rawValue
            existing.userEditedCategory = merged.userEditedCategory
            existing.isPending = merged.isPending
            existing.currencyCode = merged.currencyCode
            existing.accountID = account.id
            existing.account = account
            existing.categoryLocked = merged.categoryLocked
        } else {
            let merged = MergeSyncPolicy.merge(local: nil, remote: remoteDomain, rules: rules)
            let entity = TransactionEntity(
                id: UUID().uuidString,
                externalID: remote.externalID,
                accountID: account.id,
                amount: merged.amount,
                postedDate: merged.postedDate,
                transactionDescription: merged.description,
                categoryID: merged.categoryID.rawValue,
                currencyCode: account.currencyCode,
                userEditedCategory: merged.userEditedCategory,
                isPending: remote.isPending,
                syncKey: syncKey,
                account: account,
                categoryLocked: false
            )
            context.insert(entity)
        }
    }

    private static func removeStalePendingTransactions(
        account: AccountEntity,
        remoteExternalIDs: Set<String>,
        context: ModelContext
    ) throws {
        let accountID = account.id
        let descriptor = FetchDescriptor<TransactionEntity>(
            predicate: #Predicate<TransactionEntity> {
                $0.accountID == accountID && $0.isPending == true
            }
        )
        for entity in try context.fetch(descriptor) where !remoteExternalIDs.contains(entity.externalID) {
            context.delete(entity)
        }
    }
}
