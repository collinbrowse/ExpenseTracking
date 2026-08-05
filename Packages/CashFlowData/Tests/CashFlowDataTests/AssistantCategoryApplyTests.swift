
import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("Assistant category apply")
struct AssistantCategoryApplyTests {
    @Test("Execute categorize rule updates matching row category")
    func executeUpdatesCategory() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let account = AccountEntity(
            id: "acct",
            externalID: "ext-a",
            name: "Prime Savings",
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
                amount: Decimal(111.36),
                postedDate: Date(timeIntervalSince1970: 1_700_000_000),
                transactionDescription: "ACCR EARNING PYMT ADDED TO ACCOUNT",
                categoryID: SystemCategory.other.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext-a|u1",
                account: account,
                enrichedTitle: "Accr Earning Pymt Added to Account",
                enrichedLocation: nil
            )
        )
        try context.save()

        let assistant = IntentHostTransactionAssistant(
            availability: FixedAvailability(.available),
            intentInterpreting: FixedIntentInterpreting(
                intent: AssistantIntent(
                    explanation: "Categorize earning as Income",
                    conditions: [.titleContains("earning")],
                    appliesCategory: true,
                    categoryID: SystemCategory.income.id,
                    prefersSavingRule: true
                )
            ),
            transactionRepository: SwiftDataTransactionRepository(modelContainer: container),
            tagRepository: SwiftDataTagRepository(modelContainer: container),
            accountRepository: SwiftDataAccountRepository(modelContainer: container),
            ruleRepository: SwiftDataCategorizationRuleRepository(modelContainer: container),
            ruleApplying: CategorizationRuleReapplier(modelContainer: container)
        )

        var proposal: AssistantProposal?
        for try await event in assistant.interpret(prompt: "earning is income") {
            if case .proposal(let value) = event { proposal = value }
        }
        let p = try #require(proposal)
        #expect(p.affectedCount == 1)
        #expect(p.appliesCategory)
        #expect(p.categoryID == SystemCategory.income.id)

        _ = try await assistant.execute(p)

        let loaded = try await SwiftDataTransactionRepository(modelContainer: container)
            .fetchAllForCategorization()
        #expect(loaded.count == 1)
        #expect(loaded[0].categoryID == SystemCategory.income.id)
        #expect(loaded[0].userEditedCategory)

        let rules = try await SwiftDataCategorizationRuleRepository(modelContainer: container)
            .fetchAll()
        #expect(rules.count == 1)
        #expect(rules[0].appliesCategory)
        #expect(rules[0].categoryID == SystemCategory.income.id)
    }
}

private struct FixedAvailability: OnDeviceModelAvailabilityChecking {
    let value: OnDeviceModelAvailability
    init(_ value: OnDeviceModelAvailability) { self.value = value }
    func availability() async -> OnDeviceModelAvailability { value }
}

private struct FixedIntentInterpreting: TransactionIntentInterpreting {
    let intent: AssistantIntent
    func interpret(
        prompt: String,
        accounts: [Account],
        tags: [CashFlowKit.Tag]
    ) -> AsyncThrowingStream<AssistantIntentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.intent(intent))
            continuation.finish()
        }
    }
}
