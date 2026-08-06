import Foundation
import SwiftData
import CashFlowKit

/// Single definition of "still needs a title" so the repository, sync status, and any
/// future caller cannot drift apart on which rows count as backlog.
///
/// A row is backlog when it is posted, has no enriched title, and carries no `TitleSource`.
/// Rows retired as `TitleSource.skipped` keep a source, so they stay out of the backlog.
enum EnrichmentBacklogQuery {
    /// Upper bound on rows scanned for the approximate distinct-merchant estimate.
    static let distinctScanCap = 2_000

    static var predicate: Predicate<TransactionEntity> {
        #Predicate<TransactionEntity> {
            !$0.isPending && $0.enrichedTitle == nil && $0.titleSourceRaw == nil
        }
    }

    static func count(context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<TransactionEntity>(predicate: predicate))
    }

    /// Approximate distinct-merchant count for "about N unique merchants" copy and the
    /// large-backlog prompt. Scans at most `distinctScanCap` rows and faults in only the
    /// description column — materializing the whole backlog ran on every Settings load.
    static func distinctDescriptionCount(context: ModelContext) throws -> Int {
        var descriptor = FetchDescriptor<TransactionEntity>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.postedDate, order: .reverse)]
        )
        descriptor.fetchLimit = distinctScanCap
        descriptor.propertiesToFetch = [\.transactionDescription]
        var keys = Set<String>()
        for entity in try context.fetch(descriptor) {
            let key = TransactionDescriptionMatcher.normalize(entity.transactionDescription)
            if !key.isEmpty {
                keys.insert(key)
            }
        }
        return keys.count
    }
}
