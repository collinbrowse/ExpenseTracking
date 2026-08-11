import Foundation
import CashFlowKit
import SwiftData

/// Filtered CSV export of transactions (same `TransactionFilter` as the list UI).
public actor LocalCSVExporter: LocalDataExporting {
    private let modelContainer: ModelContainer
    private let transactionRepository: SwiftDataTransactionRepository

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.transactionRepository = SwiftDataTransactionRepository(modelContainer: modelContainer)
    }

    public func exportCSV(filter: TransactionFilter) async throws -> Data {
        do {
            let transactions = try await transactionRepository.fetchAllMatching(filter: filter)
            let context = ModelContext(modelContainer)
            let accounts = try context.fetch(FetchDescriptor<AccountEntity>())
            let accountNames = Dictionary(
                uniqueKeysWithValues: accounts.map { (AccountID($0.id), $0.name) }
            )
            let tags = try context.fetch(FetchDescriptor<TagEntity>())
            let tagNames = Dictionary(
                uniqueKeysWithValues: tags.map { (TagID($0.id), $0.name) }
            )

            var csv = "posted_date,amount,currency,title,location,category,account,tags,pending,raw_description,external_id\n"
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withFullDate]

            for tx in transactions {
                let title = tx.displayTitle
                let location = tx.displayLocation ?? ""
                let category = SystemCategory.category(for: tx.categoryID).name
                let account = accountNames[tx.accountID] ?? tx.accountID.rawValue
                let tagLabels = tx.tagIDs
                    .map { tagNames[$0] ?? $0.rawValue }
                    .sorted()
                    .joined(separator: "; ")
                let row = [
                    dateFormatter.string(from: tx.postedDate),
                    Self.decimalString(tx.amount),
                    tx.currencyCode,
                    title,
                    location,
                    category,
                    account,
                    tagLabels,
                    tx.isPending ? "true" : "false",
                    tx.description,
                    tx.externalID,
                ]
                .map(Self.escape)
                .joined(separator: ",")
                csv.append(row)
                csv.append("\n")
            }

            guard let data = csv.data(using: .utf8) else {
                throw CashFlowError.persistence(message: "Couldn’t encode CSV export.")
            }
            return data
        } catch let error as CashFlowError {
            throw error
        } catch {
            throw CashFlowError.persistence(message: "Couldn’t export CSV.")
        }
    }

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
