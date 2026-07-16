import Foundation
import SwiftData
import CashFlowKit

public actor SwiftDataTransactionRepository: TransactionRepository {
    private let modelContainer: ModelContainer
    private let scanBatchSize = 200

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func fetchPage(
        filter: TransactionFilter,
        cursor: TransactionCursor?,
        limit: Int
    ) async throws -> TransactionPage {
        let context = ModelContext(modelContainer)
        let pageItems = try fetchKeyset(
            context: context,
            filter: filter,
            cursor: cursor,
            limit: limit
        )
        let transactions = pageItems.map(EntityMappers.transaction(from:))
        let next: TransactionCursor?
        if transactions.count == limit, let last = transactions.last {
            next = TransactionCursor(transaction: last)
        } else {
            next = nil
        }
        return TransactionPage(items: transactions, nextCursor: next)
    }

    public func fetchPosted(in range: CashFlowDateRange, now: Date) async throws -> [Transaction] {
        let context = ModelContext(modelContainer)
        let interval = range.interval(now: now)
        // Avoid SwiftData #Predicate date-capture quirks; filter in memory after fetch.
        let descriptor = FetchDescriptor<TransactionEntity>(
            sortBy: [SortDescriptor(\.postedDate, order: .reverse)]
        )
        let entities = try context.fetch(descriptor)
        return entities
            .filter { entity in
                !entity.isPending
                    && entity.postedDate >= interval.start
                    && entity.postedDate <= interval.end
            }
            .map(EntityMappers.transaction(from:))
    }

    public func updateCategory(
        transactionID: TransactionID,
        categoryID: CategoryID
    ) async throws {
        let context = ModelContext(modelContainer)
        let id = transactionID.rawValue
        let predicate = #Predicate<TransactionEntity> { $0.id == id }
        var descriptor = FetchDescriptor<TransactionEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else {
            throw CashFlowError.persistence(message: "Transaction not found")
        }
        entity.categoryID = categoryID.rawValue
        entity.userEditedCategory = true
        try context.save()
    }

    public func updateDescription(
        transactionID: TransactionID,
        description: String
    ) async throws {
        let context = ModelContext(modelContainer)
        let id = transactionID.rawValue
        let predicate = #Predicate<TransactionEntity> { $0.id == id }
        var descriptor = FetchDescriptor<TransactionEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else {
            throw CashFlowError.persistence(message: "Transaction not found")
        }
        entity.transactionDescription = description
        try context.save()
    }

    /// Keyset scan that can walk the full store (no hard 1k cap) for infinite scrolling.
    private func fetchKeyset(
        context: ModelContext,
        filter: TransactionFilter,
        cursor: TransactionCursor?,
        limit: Int
    ) throws -> [TransactionEntity] {
        let calendar = Calendar.current
        let now = Date.now
        let dateInterval = filter.dateRange?.interval(calendar: calendar, now: now)
        var results: [TransactionEntity] = []
        results.reserveCapacity(limit)
        var scanCursor = cursor

        while results.count < limit {
            let batch = try fetchBatch(context: context, after: scanCursor)
            if batch.isEmpty { break }

            for entity in batch {
                if matches(entity, filter: filter, dateInterval: dateInterval) {
                    results.append(entity)
                    if results.count == limit { break }
                }
            }

            if let last = batch.last {
                scanCursor = TransactionCursor(
                    postedDate: last.postedDate,
                    id: TransactionID(last.id)
                )
            }
            if batch.count < scanBatchSize { break }
        }

        return results
    }

    private func fetchBatch(
        context: ModelContext,
        after cursor: TransactionCursor?
    ) throws -> [TransactionEntity] {
        var descriptor = FetchDescriptor<TransactionEntity>(
            sortBy: [
                SortDescriptor(\.postedDate, order: .reverse),
                SortDescriptor(\.id, order: .reverse),
            ]
        )
        descriptor.fetchLimit = scanBatchSize

        if let cursor {
            let cursorDate = cursor.postedDate
            let cursorID = cursor.id.rawValue
            descriptor.predicate = #Predicate<TransactionEntity> { entity in
                entity.isPending == false
                    && (
                        entity.postedDate < cursorDate
                            || (entity.postedDate == cursorDate && entity.id < cursorID)
                    )
            }
        } else {
            descriptor.predicate = #Predicate<TransactionEntity> { entity in
                entity.isPending == false
            }
        }

        return try context.fetch(descriptor)
    }

    private func matches(
        _ entity: TransactionEntity,
        filter: TransactionFilter,
        dateInterval: DateInterval?
    ) -> Bool {
        let entityAccountID = entity.account?.id ?? entity.accountID
        if let accountID = filter.accountID?.rawValue, entityAccountID != accountID {
            return false
        }
        if let categoryID = filter.categoryID?.rawValue, entity.categoryID != categoryID {
            return false
        }
        if let dateInterval {
            if entity.postedDate < dateInterval.start || entity.postedDate > dateInterval.end {
                return false
            }
        }
        return true
    }
}

public actor SwiftDataAccountRepository: AccountRepository {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func fetchAll() async throws -> [Account] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AccountEntity>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor).map(EntityMappers.account(from:))
    }
}
