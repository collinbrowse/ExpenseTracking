import Foundation
import SwiftData
import CashFlowKit

enum SyncMergeEngine {
    static func merge(
        payload: RemoteSyncPayload,
        into context: ModelContext
    ) throws {
        let rules = try loadRules(from: context)
        var touchedAccountExternalIDs = Set<String>()
        touchedAccountExternalIDs.reserveCapacity(payload.accounts.count)

        for remoteAccount in payload.accounts {
            touchedAccountExternalIDs.insert(remoteAccount.externalID)
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

        // Bridge may omit a failing FI from `accounts` while still reporting it in errlist.
        // Attach those leftover messages to matching local rows so Accounts doesn't stay "Sync OK".
        try applyUnmatchedProviderMessages(
            messages: payload.providerMessages,
            remoteAccounts: payload.accounts,
            excludingExternalIDs: touchedAccountExternalIDs,
            into: context
        )
        try context.save()
    }

    /// Propagates provider messages that never landed on a remote snapshot onto local accounts.
    static func applyUnmatchedProviderMessages(
        messages: [String],
        remoteAccounts: [RemoteAccountSnapshot],
        excludingExternalIDs: Set<String>,
        into context: ModelContext
    ) throws {
        let actionable = messages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !SimpleFINClient.isBenignDateRangeAdvisory($0) }
        guard !actionable.isEmpty else { return }

        let attachedMessages = Set(
            remoteAccounts.compactMap { account -> String? in
                guard let issue = account.syncIssue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !issue.isEmpty
                else { return nil }
                return issue.lowercased()
            }
        )

        let unmatched = actionable.filter { message in
            let key = message.lowercased()
            if attachedMessages.contains(key) { return false }
            // A remote syncIssue may join several messages; treat contained messages as attached.
            return !attachedMessages.contains { $0.contains(key) || key.contains($0) }
        }
        guard !unmatched.isEmpty else { return }

        let locals = try context.fetch(FetchDescriptor<AccountEntity>())
        let untouched = locals.filter { !excludingExternalIDs.contains($0.externalID) }
        guard !untouched.isEmpty else { return }

        let broadcastAll = remoteAccounts.isEmpty
        for account in untouched {
            let matching = unmatched.filter { message in
                if broadcastAll { return true }
                return SimpleFINClient.messageMatchesAccountIdentity(
                    message,
                    name: account.name,
                    institutionName: account.institutionName
                )
            }
            guard !matching.isEmpty else { continue }
            account.syncIssue = SimpleFINClient.mergeSyncIssues(
                account.syncIssue,
                matching.joined(separator: " ")
            )
        }
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
            let merged = MergeSyncPolicy.merge(
                local: local,
                remote: remoteDomain,
                rules: rules,
                preferSuggestedCategory: remote.preferSuggestedCategory
            )
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
            existing.enrichedTitle = merged.enrichedTitle
            existing.enrichedLocation = merged.enrichedLocation
            existing.titleSourceRaw = EntityMappers.titleSourceRaw(from: merged.titleSource)
            existing.categorySourceRaw = EntityMappers.categorySourceRaw(from: merged.categorySource)
            existing.suppressedTagIDsData = try EntityMappers.encodeTagIDs(merged.suppressedTagIDs)
            try applyTags(merged.tagIDs, to: existing, context: context)
        } else {
            let merged = MergeSyncPolicy.merge(
                local: nil,
                remote: remoteDomain,
                rules: rules,
                preferSuggestedCategory: remote.preferSuggestedCategory
            )
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
                categoryLocked: false,
                enrichedTitle: merged.enrichedTitle,
                enrichedLocation: merged.enrichedLocation,
                titleSourceRaw: EntityMappers.titleSourceRaw(from: merged.titleSource),
                categorySourceRaw: EntityMappers.categorySourceRaw(from: merged.categorySource),
                suppressedTagIDsData: try EntityMappers.encodeTagIDs(merged.suppressedTagIDs)
            )
            context.insert(entity)
            try applyTags(merged.tagIDs, to: entity, context: context)
        }
    }

    private static func applyTags(
        _ tagIDs: [TagID],
        to entity: TransactionEntity,
        context: ModelContext
    ) throws {
        let uniqueIDs = Array(Set(tagIDs.map(\.rawValue)))
        guard !uniqueIDs.isEmpty else {
            // Rules never clear user tags; only write when there is something to attach.
            return
        }
        let predicate = #Predicate<TagEntity> { uniqueIDs.contains($0.id) }
        let tags = try context.fetch(FetchDescriptor<TagEntity>(predicate: predicate))
        var byID = Dictionary(uniqueKeysWithValues: entity.tags.map { ($0.id, $0) })
        for tag in tags {
            byID[tag.id] = tag
        }
        // Keep any local tags that still exist; add resolved rule tags.
        entity.tags = Array(byID.values)
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
