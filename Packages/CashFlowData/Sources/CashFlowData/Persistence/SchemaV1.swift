import Foundation
import SwiftData

public enum CashFlowSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [AccountEntity.self, TransactionEntity.self, ConnectionEntity.self]
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

    @Relationship(deleteRule: .cascade, inverse: \TransactionEntity.account)
    public var transactions: [TransactionEntity]

    public init(
        id: String,
        externalID: String,
        name: String,
        institutionName: String,
        currencyCode: String,
        balance: Decimal,
        balanceDate: Date
    ) {
        self.id = id
        self.externalID = externalID
        self.name = name
        self.institutionName = institutionName
        self.currencyCode = currencyCode
        self.balance = balance
        self.balanceDate = balanceDate
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
    /// Composite uniqueness helper: accountExternalID + transactionExternalID
    @Attribute(.unique) public var syncKey: String

    public var account: AccountEntity?

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
        account: AccountEntity?
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
    }
}

@Model
public final class ConnectionEntity {
    @Attribute(.unique) public var id: String
    public var providerName: String
    public var needsReauth: Bool
    public var lastSuccessfulSyncAt: Date?
    public var isDemo: Bool

    public init(
        id: String = "primary",
        providerName: String,
        needsReauth: Bool = false,
        lastSuccessfulSyncAt: Date? = nil,
        isDemo: Bool = false
    ) {
        self.id = id
        self.providerName = providerName
        self.needsReauth = needsReauth
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.isDemo = isDemo
    }
}
