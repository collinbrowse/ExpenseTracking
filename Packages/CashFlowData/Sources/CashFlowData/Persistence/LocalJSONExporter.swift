import Foundation
import CashFlowKit
import SwiftData

/// Store-wide JSON export of the local ledger. Omits Keychain secrets and memo cache.
public actor LocalJSONExporter: LocalDataExporting {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func exportJSON() async throws -> Data {
        let context = ModelContext(modelContainer)
        do {
            let accountEntities = try context.fetch(FetchDescriptor<AccountEntity>())
            let transactionEntities = try context.fetch(FetchDescriptor<TransactionEntity>())
            let tagEntities = try context.fetch(FetchDescriptor<TagEntity>())
            let ruleEntities = try context.fetch(FetchDescriptor<CategorizationRuleEntity>())
            let connectionEntities = try context.fetch(FetchDescriptor<ConnectionEntity>())

            let accounts = accountEntities
                .map(Self.exportAccount(from:))
                .sorted { $0.id.rawValue < $1.id.rawValue }
            let transactions = transactionEntities
                .map(EntityMappers.transaction(from:))
                .sorted { $0.id.rawValue < $1.id.rawValue }
            let tags = tagEntities
                .map(EntityMappers.tag(from:))
                .sorted { $0.id.rawValue < $1.id.rawValue }
            let rules = try ruleEntities.map(EntityMappers.categorizationRule(from:))
                .sorted { $0.priority < $1.priority }
            let connection = connectionEntities.first.map(Self.exportConnection(from:))

            let document = LocalDataExportDocument(
                exportedAt: Date(),
                accounts: accounts,
                transactions: transactions,
                tags: tags,
                rules: rules,
                connection: connection
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            return try encoder.encode(document)
        } catch let error as CashFlowError {
            throw error
        } catch {
            throw CashFlowError.persistence(message: "Couldn’t export local data.")
        }
    }

    private static func exportAccount(from entity: AccountEntity) -> LocalDataExportAccount {
        LocalDataExportAccount(
            id: AccountID(entity.id),
            externalID: entity.externalID,
            name: entity.name,
            institutionName: entity.institutionName,
            currencyCode: entity.currencyCode,
            balance: entity.balance,
            balanceDate: entity.balanceDate,
            syncIssue: entity.syncIssue,
            userEditedName: entity.userEditedName,
            connectionExternalID: entity.connectionExternalID
        )
    }

    private static func exportConnection(from entity: ConnectionEntity) -> LocalDataExportConnection {
        LocalDataExportConnection(
            id: entity.id,
            providerName: entity.providerName,
            needsReauth: entity.needsReauth,
            lastSuccessfulSyncAt: entity.lastSuccessfulSyncAt,
            isDemo: entity.isDemo,
            earliestFetchedDate: entity.earliestFetchedDate,
            lookbackYears: entity.lookbackYearsRaw,
            historyComplete: entity.historyComplete
        )
    }
}
