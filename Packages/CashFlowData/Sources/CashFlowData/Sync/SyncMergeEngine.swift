import Foundation
import SwiftData
import CashFlowKit

enum SyncMergeEngine {
    static func merge(
        payload: RemoteSyncPayload,
        into context: ModelContext
    ) throws {
        for remoteAccount in payload.accounts {
            let account = try upsertAccount(remoteAccount, context: context)
            for remoteTx in remoteAccount.transactions {
                if remoteTx.isPending { continue }
                if remoteTx.postedDate.timeIntervalSince1970 == 0 { continue }
                try upsertTransaction(remoteTx, account: account, context: context)
            }
        }
        try context.save()
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
            userEditedName: false
        )
        context.insert(entity)
        return entity
    }

    private static func upsertTransaction(
        _ remote: RemoteTransactionSnapshot,
        account: AccountEntity,
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
            isPending: remote.isPending
        )

        if let existing = try context.fetch(descriptor).first {
            let local = EntityMappers.transaction(from: existing)
            let merged = MergeSyncPolicy.merge(local: local, remote: remoteDomain)
            existing.amount = merged.amount
            existing.postedDate = merged.postedDate
            existing.transactionDescription = merged.description
            existing.categoryID = merged.categoryID.rawValue
            existing.userEditedCategory = merged.userEditedCategory
            existing.isPending = merged.isPending
            existing.currencyCode = merged.currencyCode
            existing.accountID = account.id
            existing.account = account
        } else {
            let entity = TransactionEntity(
                id: UUID().uuidString,
                externalID: remote.externalID,
                accountID: account.id,
                amount: remote.amount,
                postedDate: remote.postedDate,
                transactionDescription: remote.description,
                categoryID: remote.suggestedCategoryID.rawValue,
                currencyCode: account.currencyCode,
                userEditedCategory: false,
                isPending: remote.isPending,
                syncKey: syncKey,
                account: account
            )
            context.insert(entity)
        }
    }
}
