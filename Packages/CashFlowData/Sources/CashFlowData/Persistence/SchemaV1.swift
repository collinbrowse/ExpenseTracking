import Foundation
import CashFlowKit
@preconcurrency import SwiftData

/// Single versioned schema.
///
/// Do not add parallel `VersionedSchema` enums that list the same `@Model` types —
/// SwiftData checksums the live model shape, so identical stages crash with
/// `Duplicate version checksums detected`. Additive fields use defaults on the
/// `@Model` types; incompatible stores are wiped in `ModelContainerFactory`.
public enum CashFlowSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            AccountEntity.self,
            TransactionEntity.self,
            ConnectionEntity.self,
            CategorizationRuleEntity.self,
            TagEntity.self,
            MerchantParseMemoEntity.self,
        ]
    }
}

public enum CashFlowMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CashFlowSchemaV1.self]
    }

    public static var stages: [MigrationStage] { [] }
}

@Model
public final class AccountEntity {
    @Attribute(.unique) public var id: String
    @Attribute(.unique) public var externalID: String
    public var name: String
    public var institutionName: String
    public var currencyCode: String
    public var balance: Decimal
    public var balanceDate: Date
    /// When true, sync keeps local `name` and does not apply SimpleFIN's account name.
    /// Default on the property (not only init) so lightweight migration can fill existing rows.
    public var userEditedName: Bool = false
    /// SimpleFIN Bridge connection id for scoping provider errors.
    public var connectionExternalID: String?
    /// Last provider sync issue for this account; `nil` means healthy.
    public var syncIssue: String?

    @Relationship(deleteRule: .cascade, inverse: \TransactionEntity.account)
    public var transactions: [TransactionEntity] = []

    public init(
        id: String,
        externalID: String,
        name: String,
        institutionName: String,
        currencyCode: String,
        balance: Decimal,
        balanceDate: Date,
        userEditedName: Bool = false,
        connectionExternalID: String? = nil,
        syncIssue: String? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.name = name
        self.institutionName = institutionName
        self.currencyCode = currencyCode
        self.balance = balance
        self.balanceDate = balanceDate
        self.userEditedName = userEditedName
        self.connectionExternalID = connectionExternalID
        self.syncIssue = syncIssue
        self.transactions = []
    }
}

@Model
public final class TransactionEntity {
    @Attribute(.unique) public var id: String
    public var externalID: String
    /// Denormalized local account id so mapping does not depend on relationship faults.
    public var accountID: String = ""
    public var amount: Decimal
    public var postedDate: Date
    public var transactionDescription: String
    public var categoryID: String
    public var currencyCode: String
    public var userEditedCategory: Bool
    public var isPending: Bool
    /// When true, user categorization rules never change this row’s category.
    public var categoryLocked: Bool = false
    /// Local-only merchant title from on-device enrichment; sync never invents this.
    public var enrichedTitle: String?
    /// Local-only location from on-device enrichment; sync never invents this.
    public var enrichedLocation: String?
    /// `TitleSource.rawValue` for the enrichment fields; nil when no enrichment is present.
    public var titleSourceRaw: String? = nil
    /// JSON-encoded `[TagID]` the user removed; rules must not re-add these.
    public var suppressedTagIDsData: Data? = nil
    /// Composite uniqueness helper: accountExternalID + transactionExternalID
    @Attribute(.unique) public var syncKey: String

    public var account: AccountEntity?

    /// Local-only tags; sync upserts never clear this relationship.
    @Relationship(inverse: \TagEntity.transactions)
    public var tags: [TagEntity] = []

    public init(
        id: String,
        externalID: String,
        accountID: String,
        amount: Decimal,
        postedDate: Date,
        transactionDescription: String,
        categoryID: String,
        currencyCode: String,
        userEditedCategory: Bool,
        isPending: Bool,
        syncKey: String,
        account: AccountEntity?,
        categoryLocked: Bool = false,
        enrichedTitle: String? = nil,
        enrichedLocation: String? = nil,
        titleSourceRaw: String? = nil,
        suppressedTagIDsData: Data? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.accountID = accountID
        self.amount = amount
        self.postedDate = postedDate
        self.transactionDescription = transactionDescription
        self.categoryID = categoryID
        self.currencyCode = currencyCode
        self.userEditedCategory = userEditedCategory
        self.isPending = isPending
        self.syncKey = syncKey
        self.account = account
        self.categoryLocked = categoryLocked
        self.enrichedTitle = enrichedTitle
        self.enrichedLocation = enrichedLocation
        self.titleSourceRaw = titleSourceRaw
        self.suppressedTagIDsData = suppressedTagIDsData
        self.tags = []
    }
}

@Model
public final class ConnectionEntity {
    @Attribute(.unique) public var id: String
    public var providerName: String
    public var needsReauth: Bool
    public var lastSuccessfulSyncAt: Date?
    public var isDemo: Bool = false
    /// Oldest posted date the provider has been asked for so far; nil before the first sync.
    public var earliestFetchedDate: Date? = nil
    /// `HistoryLookbackYears.rawValue` the user asked us to import.
    public var lookbackYearsRaw: Int = 2
    /// True once the backward walk reached the target start date or the bank ran dry.
    public var historyComplete: Bool = false
    /// Last time the backward walk actually moved `earliestFetchedDate` older.
    public var lastBackfillAdvanceAt: Date? = nil
    /// Legacy flag kept for lightweight migration from stores that still have the column.
    public var historyBackfillComplete: Bool = false

    public init(
        id: String = "primary",
        providerName: String,
        needsReauth: Bool = false,
        lastSuccessfulSyncAt: Date? = nil,
        isDemo: Bool = false,
        earliestFetchedDate: Date? = nil,
        lookbackYearsRaw: Int = 2,
        historyComplete: Bool = false,
        lastBackfillAdvanceAt: Date? = nil,
        historyBackfillComplete: Bool = false
    ) {
        self.id = id
        self.providerName = providerName
        self.needsReauth = needsReauth
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.isDemo = isDemo
        self.earliestFetchedDate = earliestFetchedDate
        self.lookbackYearsRaw = lookbackYearsRaw
        self.historyComplete = historyComplete
        self.lastBackfillAdvanceAt = lastBackfillAdvanceAt
        self.historyBackfillComplete = historyBackfillComplete
    }

    public var lookback: HistoryLookbackYears {
        HistoryLookbackYears(rawValue: lookbackYearsRaw) ?? .default
    }
}

@Model
public final class CategorizationRuleEntity {
    @Attribute(.unique) public var id: String
    public var categoryID: String
    public var priority: Int
    public var isEnabled: Bool = true
    /// JSON-encoded `[CategorizationCondition]`.
    public var conditionsData: Data
    /// Optional merchant title applied when the rule matches.
    public var renameTitle: String? = nil
    /// Optional location applied when the rule matches.
    public var renameLocation: String? = nil
    /// When false, matching only renames / tags; category is left alone.
    public var appliesCategory: Bool = true
    /// JSON-encoded `[TagID]` added when the rule matches.
    public var tagIDsData: Data? = nil
    /// True when the assistant created this rule.
    public var createdByAssistant: Bool = false
    /// JSON-encoded `CategorizationRuleApplySnapshot` from the last apply.
    public var applySnapshotData: Data? = nil

    public init(
        id: String,
        categoryID: String,
        priority: Int,
        isEnabled: Bool = true,
        conditionsData: Data,
        renameTitle: String? = nil,
        renameLocation: String? = nil,
        appliesCategory: Bool = true,
        tagIDsData: Data? = nil,
        createdByAssistant: Bool = false,
        applySnapshotData: Data? = nil
    ) {
        self.id = id
        self.categoryID = categoryID
        self.priority = priority
        self.isEnabled = isEnabled
        self.conditionsData = conditionsData
        self.renameTitle = renameTitle
        self.renameLocation = renameLocation
        self.appliesCategory = appliesCategory
        self.tagIDsData = tagIDsData
        self.createdByAssistant = createdByAssistant
        self.applySnapshotData = applySnapshotData
    }
}

@Model
public final class TagEntity {
    @Attribute(.unique) public var id: String
    public var name: String
    public var createdAt: Date
    public var transactions: [TransactionEntity] = []

    public init(id: String, name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.transactions = []
    }
}

/// Memoized LLM parse keyed by normalized bank description.
@Model
public final class MerchantParseMemoEntity {
    @Attribute(.unique) public var normalizedKey: String
    public var title: String
    public var location: String?
    public var version: Int = 1
    public var createdAt: Date = Date()

    public init(
        normalizedKey: String,
        title: String,
        location: String? = nil,
        version: Int = 1,
        createdAt: Date = .now
    ) {
        self.normalizedKey = normalizedKey
        self.title = title
        self.location = location
        self.version = version
        self.createdAt = createdAt
    }
}
