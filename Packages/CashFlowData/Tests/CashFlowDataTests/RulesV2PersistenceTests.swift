import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("Rules 2.0 persistence")
struct RulesV2PersistenceTests {
    @Test("Rule mapper round-trips tag actions and assistant provenance")
    func ruleRoundTrip() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let repo = SwiftDataCategorizationRuleRepository(modelContainer: container)
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.travelVacation.id,
            priority: 0,
            conditions: [.locationContains("Thailand")],
            appliesCategory: false,
            tagIDs: [TagID("t1")],
            createdByAssistant: true
        )
        try await repo.upsert(rule)
        let loaded = try await repo.fetchAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].tagIDs == [TagID("t1")])
        #expect(loaded[0].createdByAssistant)
        #expect(loaded[0].conditions == [.locationContains("Thailand")])

        // Editing preserves assistant badge.
        var edited = loaded[0]
        edited = CategorizationRule(
            id: edited.id,
            categoryID: edited.categoryID,
            priority: edited.priority,
            isEnabled: edited.isEnabled,
            conditions: edited.conditions,
            appliesCategory: false,
            tagIDs: [TagID("t1"), TagID("t2")],
            createdByAssistant: false
        )
        try await repo.upsert(edited)
        let again = try await repo.fetchAll()
        #expect(again[0].createdByAssistant)
        #expect(again[0].tagIDs.count == 2)
    }

    @Test("updateTags records suppressions; reapply honors them")
    func suppressionsSurviveReapply() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let account = AccountEntity(
            id: "acct",
            externalID: "ext-a",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 100,
            balanceDate: .now
        )
        context.insert(account)
        let tagA = TagEntity(id: "tag-a", name: "Thailand", createdAt: .now)
        let tagB = TagEntity(id: "tag-b", name: "Asia", createdAt: .now)
        context.insert(tagA)
        context.insert(tagB)
        let tx = TransactionEntity(
            id: "t1",
            externalID: "u1",
            accountID: account.id,
            amount: -5,
            postedDate: Date(timeIntervalSince1970: 1_700_000_000),
            transactionDescription: "Trip Cafe",
            categoryID: SystemCategory.other.id.rawValue,
            currencyCode: "USD",
            userEditedCategory: false,
            isPending: false,
            syncKey: "ext-a|u1",
            account: account
        )
        tx.tags = [tagA, tagB]
        context.insert(tx)
        try context.save()

        let transactions = SwiftDataTransactionRepository(modelContainer: container)
        try await transactions.updateTags(
            transactionID: TransactionID("t1"),
            tagIDs: [TagID("tag-b")]
        )
        var loaded = try await transactions.fetchAllForCategorization()
        #expect(loaded[0].tagIDs == [TagID("tag-b")])
        #expect(loaded[0].suppressedTagIDs == [TagID("tag-a")])

        let rules = SwiftDataCategorizationRuleRepository(modelContainer: container)
        try await rules.upsert(
            CategorizationRule(
                id: CategorizationRuleID("r1"),
                categoryID: SystemCategory.other.id,
                priority: 0,
                conditions: [.titleContains("Trip")],
                appliesCategory: false,
                tagIDs: [TagID("tag-a"), TagID("tag-b")]
            )
        )
        let reapplier = CategorizationRuleReapplier(modelContainer: container)
        _ = try await reapplier.reapplyAllRules()
        loaded = try await transactions.fetchAllForCategorization()
        #expect(Set(loaded[0].tagIDs) == Set([TagID("tag-b")]))
        #expect(loaded[0].suppressedTagIDs == [TagID("tag-a")])
    }

    @Test("Deleting a tag strips rule references and disables empty-condition rules")
    func deleteTagCleansRules() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let tags = SwiftDataTagRepository(modelContainer: container)
        let created = try await tags.create(name: "Temp")
        let rules = SwiftDataCategorizationRuleRepository(modelContainer: container)
        try await rules.upsert(
            CategorizationRule(
                id: CategorizationRuleID("r1"),
                categoryID: SystemCategory.other.id,
                priority: 0,
                conditions: [.hasTag(created.id)],
                appliesCategory: false,
                tagIDs: [created.id]
            )
        )
        try await tags.delete(id: created.id)
        let loaded = try await rules.fetchAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].conditions.isEmpty)
        #expect(loaded[0].isEnabled == false)
        #expect(loaded[0].tagIDs.isEmpty)
    }

    @Test("applyAndCaptureUndo then undo restores; manual category wins")
    func applyUndoManualWins() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let account = AccountEntity(
            id: "acct",
            externalID: "ext-a",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 100,
            balanceDate: .now
        )
        context.insert(account)
        context.insert(
            TransactionEntity(
                id: "t1",
                externalID: "u1",
                accountID: account.id,
                amount: -12,
                postedDate: Date(timeIntervalSince1970: 1_700_000_000),
                transactionDescription: "STARBUCKS STORE",
                categoryID: SystemCategory.other.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext-a|u1",
                account: account
            )
        )
        context.insert(
            TransactionEntity(
                id: "t2",
                externalID: "u2",
                accountID: account.id,
                amount: -8,
                postedDate: Date(timeIntervalSince1970: 1_700_000_100),
                transactionDescription: "STARBUCKS RESERVE",
                categoryID: SystemCategory.other.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext-a|u2",
                account: account
            )
        )
        try context.save()

        let reapplier = CategorizationRuleReapplier(modelContainer: container)
        let rule = CategorizationRule(
            id: CategorizationRuleID("r1"),
            categoryID: SystemCategory.dining.id,
            priority: 0,
            conditions: [.titleContains("Starbucks")],
            appliesCategory: true
        )
        let saved = try await reapplier.applyAndCaptureUndo(for: rule)
        #expect(saved.canUndoApply)

        let txs = SwiftDataTransactionRepository(modelContainer: container)
        try await txs.updateCategory(
            transactionID: TransactionID("t2"),
            categoryID: SystemCategory.shopping.id,
            categoryLocked: false
        )

        let restored = try await reapplier.undoRule(id: rule.id)
        #expect(restored == 1)

        let loaded = try await txs.fetchAllForCategorization()
        let byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        #expect(byID[TransactionID("t1")]?.categoryID == SystemCategory.other.id)
        #expect(byID[TransactionID("t2")]?.categoryID == SystemCategory.shopping.id)

        let rules = try await SwiftDataCategorizationRuleRepository(modelContainer: container)
            .fetchAll()
        #expect(rules[0].isEnabled == false)
        #expect(rules[0].canUndoApply == false)
    }

    @Test("Reapply categorizes using enriched display title (CDLE regression)")
    func reapplyUsesEnrichedTitle() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let account = AccountEntity(
            id: "acct",
            externalID: "ext-a",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 100,
            balanceDate: .now
        )
        context.insert(account)
        context.insert(
            TransactionEntity(
                id: "t1",
                externalID: "u1",
                accountID: account.id,
                amount: 500,
                postedDate: Date(timeIntervalSince1970: 1_700_000_000),
                transactionDescription: "COLORADO DEPT LABOR UI PAYMENT",
                categoryID: SystemCategory.transfer.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext-a|u1",
                account: account,
                enrichedTitle: "CDLE UI BENEFITS UI PAYMENT"
            )
        )
        try context.save()

        let rules = SwiftDataCategorizationRuleRepository(modelContainer: container)
        try await rules.upsert(
            CategorizationRule(
                id: CategorizationRuleID("r1"),
                categoryID: SystemCategory.income.id,
                priority: 0,
                conditions: [.titleContains("CDLE")],
                appliesCategory: true,
                createdByAssistant: true
            )
        )
        let changed = try await CategorizationRuleReapplier(modelContainer: container)
            .reapplyAllRules()
        #expect(changed == 1)

        let loaded = try await SwiftDataTransactionRepository(modelContainer: container)
            .fetchAllForCategorization()
        #expect(loaded[0].categoryID == SystemCategory.income.id)
        #expect(loaded[0].userEditedCategory)
    }

    @Test("On-disk store survives additive schema fields with defaults")
    func additiveFieldsSurviveReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CashFlowRulesV2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let schema = Schema(versionedSchema: CashFlowSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            url: directory.appendingPathComponent("store.sqlite")
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CashFlowMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let conditions = try JSONEncoder().encode([CategorizationCondition.titleContains("Coffee")])
        context.insert(
            CategorizationRuleEntity(
                id: "legacy",
                categoryID: SystemCategory.dining.id.rawValue,
                priority: 0,
                conditionsData: conditions
            )
        )
        let account = AccountEntity(
            id: "acct",
            externalID: "ext",
            name: "Checking",
            institutionName: "Bank",
            currencyCode: "USD",
            balance: 1,
            balanceDate: .now
        )
        context.insert(account)
        context.insert(
            TransactionEntity(
                id: "t1",
                externalID: "e1",
                accountID: account.id,
                amount: -1,
                postedDate: .now,
                transactionDescription: "Coffee",
                categoryID: SystemCategory.dining.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext|e1",
                account: account
            )
        )
        try context.save()

        // Re-open the same store URL and assert defaults for new fields.
        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: CashFlowMigrationPlan.self,
            configurations: [configuration]
        )
        let reopenContext = ModelContext(reopened)
        let rules = try reopenContext.fetch(FetchDescriptor<CategorizationRuleEntity>())
        #expect(rules.count == 1)
        #expect(rules[0].createdByAssistant == false)
        #expect(rules[0].tagIDsData == nil)
        let txs = try reopenContext.fetch(FetchDescriptor<TransactionEntity>())
        #expect(txs.count == 1)
        #expect(txs[0].suppressedTagIDsData == nil)
        let mapped = try EntityMappers.categorizationRule(from: rules[0])
        #expect(mapped.tagIDs.isEmpty)
        #expect(mapped.createdByAssistant == false)
    }
}
