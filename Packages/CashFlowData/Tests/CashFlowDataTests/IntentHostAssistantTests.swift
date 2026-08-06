import Foundation
import SwiftData
import Testing
import CashFlowKit
@testable import CashFlowData

@Suite("IntentHostTransactionAssistant")
struct IntentHostAssistantTests {
    @Test("Proposal count matches rows affected by saved rule on reapply")
    func proposalParityWithRule() async throws {
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
        for index in 0..<3 {
            context.insert(
                TransactionEntity(
                    id: "t\(index)",
                    externalID: "u\(index)",
                    accountID: account.id,
                    amount: Decimal(-10 - index),
                    postedDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                    transactionDescription: "Bangkok Cafe \(index)",
                    categoryID: SystemCategory.other.id.rawValue,
                    currencyCode: "USD",
                    userEditedCategory: false,
                    isPending: false,
                    syncKey: "ext-a|u\(index)",
                    account: account,
                    enrichedTitle: "Cafe \(index)",
                    enrichedLocation: "Bangkok Thailand"
                )
            )
        }
        // Non-matching row
        context.insert(
            TransactionEntity(
                id: "other",
                externalID: "other",
                accountID: account.id,
                amount: -9,
                postedDate: Date(timeIntervalSince1970: 1_700_000_500),
                transactionDescription: "Seattle Coffee",
                categoryID: SystemCategory.other.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext-a|other",
                account: account,
                enrichedTitle: "Coffee",
                enrichedLocation: "Seattle WA"
            )
        )
        try context.save()

        let intent = FixedIntentInterpreting(
            intent: AssistantIntent(
                explanation: "Tag Thailand spend",
                conditions: [.locationContains("Thailand")],
                appliesCategory: false,
                categoryID: SystemCategory.other.id,
                tagNames: ["Southeast Asia"],
                prefersSavingRule: true
            )
        )
        let assistant = IntentHostTransactionAssistant(
            availability: FixedAvailability(.available),
            intentInterpreting: intent,
            transactionRepository: SwiftDataTransactionRepository(modelContainer: container),
            tagRepository: SwiftDataTagRepository(modelContainer: container),
            accountRepository: SwiftDataAccountRepository(modelContainer: container),
            ruleRepository: SwiftDataCategorizationRuleRepository(modelContainer: container),
            ruleApplying: CategorizationRuleReapplier(modelContainer: container),
            workCoordinator: FoundationModelsWorkCoordinator()
        )

        let proposal = try await Self.collectProposal(
            from: await assistant.interpret(prompt: "Tag Thailand")
        )
        #expect(proposal.affectedCount == 3)
        #expect(proposal.saveAsRule)
        // Newest first (t2 has the latest postedDate among matches).
        #expect(proposal.samples.map(\.id) == [
            TransactionID("t2"),
            TransactionID("t1"),
            TransactionID("t0"),
        ])
        #expect(proposal.matchingTransactionIDs == [
            TransactionID("t2"),
            TransactionID("t1"),
            TransactionID("t0"),
        ])

        let turn = try await assistant.execute(proposal)
        #expect(turn.undoSnapshot == nil)
        #expect(turn.message.text.contains("• Updated 3"))
        #expect(turn.message.text.contains("• Saved rule"))
        #expect(turn.message.text.contains("• Undo from Rules"))

        let txs = try await SwiftDataTransactionRepository(modelContainer: container)
            .fetchAllForCategorization()
        let tagged = txs.filter { !$0.tagIDs.isEmpty }
        #expect(tagged.count == 3)

        let rules = try await SwiftDataCategorizationRuleRepository(modelContainer: container)
            .fetchAll()
        #expect(rules.count == 1)
        #expect(rules[0].isEnabled)
        #expect(rules[0].createdByAssistant)
        #expect(rules[0].canUndoApply)

        let restored = try await CategorizationRuleReapplier(modelContainer: container)
            .undoRule(id: rules[0].id)
        #expect(restored == 3)
        let afterUndo = try await SwiftDataCategorizationRuleRepository(modelContainer: container)
            .fetchAll()
        #expect(afterUndo[0].isEnabled == false)
        #expect(afterUndo[0].canUndoApply == false)
        let untagged = try await SwiftDataTransactionRepository(modelContainer: container)
            .fetchAllForCategorization()
            .filter { !$0.tagIDs.isEmpty }
        #expect(untagged.isEmpty)
    }

    @Test("Dedupe updates the same rule instead of creating a second")
    func dedupe() async throws {
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
                amount: -5,
                postedDate: .now,
                transactionDescription: "Coffee",
                categoryID: SystemCategory.other.id.rawValue,
                currencyCode: "USD",
                userEditedCategory: false,
                isPending: false,
                syncKey: "ext-a|u1",
                account: account
            )
        )
        try context.save()

        let intent = FixedIntentInterpreting(
            intent: AssistantIntent(
                explanation: "Dining",
                conditions: [.titleContains("Coffee")],
                appliesCategory: true,
                categoryID: SystemCategory.dining.id,
                prefersSavingRule: true
            )
        )
        let assistant = IntentHostTransactionAssistant(
            availability: FixedAvailability(.available),
            intentInterpreting: intent,
            transactionRepository: SwiftDataTransactionRepository(modelContainer: container),
            tagRepository: SwiftDataTagRepository(modelContainer: container),
            accountRepository: SwiftDataAccountRepository(modelContainer: container),
            ruleRepository: SwiftDataCategorizationRuleRepository(modelContainer: container),
            ruleApplying: CategorizationRuleReapplier(modelContainer: container),
            workCoordinator: FoundationModelsWorkCoordinator()
        )
        let proposal = try await Self.collectProposal(
            from: await assistant.interpret(prompt: "Coffee is dining")
        )
        _ = try await assistant.execute(proposal)
        _ = try await assistant.execute(proposal)
        let rules = try await SwiftDataCategorizationRuleRepository(modelContainer: container)
            .fetchAll()
        #expect(rules.count == 1)
    }

    @Test("Interpret stream emits status then proposal")
    func interpretStreamPhases() async throws {
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
        try context.save()

        let assistant = IntentHostTransactionAssistant(
            availability: FixedAvailability(.available),
            intentInterpreting: FixedIntentInterpreting(
                intent: AssistantIntent(
                    explanation: "Tag trip",
                    conditions: [.locationContains("Paris")],
                    appliesCategory: false,
                    categoryID: SystemCategory.other.id,
                    tagNames: ["Trip"],
                    prefersSavingRule: true
                )
            ),
            transactionRepository: SwiftDataTransactionRepository(modelContainer: container),
            tagRepository: SwiftDataTagRepository(modelContainer: container),
            accountRepository: SwiftDataAccountRepository(modelContainer: container),
            ruleRepository: SwiftDataCategorizationRuleRepository(modelContainer: container),
            ruleApplying: CategorizationRuleReapplier(modelContainer: container),
            workCoordinator: FoundationModelsWorkCoordinator()
        )

        var statuses: [String] = []
        var sawProposal = false
        for try await event in await assistant.interpret(prompt: "Tag Paris") {
            switch event {
            case .status(let text):
                statuses.append(text)
            case .draft:
                break
            case .proposal:
                sawProposal = true
            }
        }
        #expect(statuses.contains(where: { $0.contains("Understanding") }))
        #expect(statuses.contains(where: { $0.contains("Finding matching") }))
        #expect(sawProposal)
    }

    private static func collectProposal(
        from stream: AsyncThrowingStream<AssistantInterpretEvent, Error>
    ) async throws -> AssistantProposal {
        var proposal: AssistantProposal?
        for try await event in stream {
            if case .proposal(let value) = event {
                proposal = value
            }
        }
        guard let proposal else {
            throw CashFlowError.intelligence(message: "Missing proposal")
        }
        return proposal
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
            continuation.yield(
                .draft(explanation: intent.explanation, conditionSummary: "…")
            )
            continuation.yield(.intent(intent))
            continuation.finish()
        }
    }
}
