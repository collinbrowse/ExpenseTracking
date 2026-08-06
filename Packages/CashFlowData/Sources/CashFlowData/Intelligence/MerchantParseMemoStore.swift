import Foundation
import SwiftData
import CashFlowKit

/// SwiftData-backed memo of validated merchant parses keyed by normalized bank description.
public actor MerchantParseMemoStore {
    public static let currentVersion = 1

    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    public func lookup(rawDescription: String) throws -> ParsedTransactionDescription? {
        let key = TransactionDescriptionMatcher.normalize(rawDescription)
        guard !key.isEmpty else { return nil }
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<MerchantParseMemoEntity> { $0.normalizedKey == key }
        var descriptor = FetchDescriptor<MerchantParseMemoEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first,
              entity.version == Self.currentVersion
        else { return nil }
        return ParsedTransactionDescription(
            title: entity.title,
            location: entity.location,
            raw: rawDescription
        )
    }

    public func store(_ parsed: ParsedTransactionDescription) throws {
        let key = TransactionDescriptionMatcher.normalize(parsed.raw)
        guard !key.isEmpty, !parsed.title.isEmpty else { return }
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<MerchantParseMemoEntity> { $0.normalizedKey == key }
        var descriptor = FetchDescriptor<MerchantParseMemoEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.title = parsed.title
            existing.location = parsed.location
            existing.version = Self.currentVersion
        } else {
            context.insert(
                MerchantParseMemoEntity(
                    normalizedKey: key,
                    title: parsed.title,
                    location: parsed.location,
                    version: Self.currentVersion
                )
            )
        }
        try context.save()
    }
}
