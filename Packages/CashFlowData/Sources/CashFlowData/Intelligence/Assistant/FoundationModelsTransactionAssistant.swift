import Foundation
import CashFlowKit

/// Host that interprets intent via a small LLM call, then matches/applies with Swift.
public actor IntentHostTransactionAssistant: TransactionAssistantServing {
    private let availability: any OnDeviceModelAvailabilityChecking
    private let intentInterpreting: any TransactionIntentInterpreting
    private let transactionRepository: any TransactionRepository
    private let tagRepository: any TagRepository
    private let accountRepository: any AccountRepository
    private let ruleRepository: any CategorizationRuleRepository
    private let ruleApplying: any CategorizationRuleApplying
    private let actionStore: AssistantActionStore
    private let workCoordinator: FoundationModelsWorkCoordinator

    public init(
        availability: any OnDeviceModelAvailabilityChecking,
        intentInterpreting: any TransactionIntentInterpreting,
        transactionRepository: any TransactionRepository,
        tagRepository: any TagRepository,
        accountRepository: any AccountRepository,
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        actionStore: AssistantActionStore = AssistantActionStore(),
        workCoordinator: FoundationModelsWorkCoordinator
    ) {
        self.availability = availability
        self.intentInterpreting = intentInterpreting
        self.transactionRepository = transactionRepository
        self.tagRepository = tagRepository
        self.accountRepository = accountRepository
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.actionStore = actionStore
        self.workCoordinator = workCoordinator
    }

    public func reset() async {
        await actionStore.discardUndo()
    }

    public func lastUndoSnapshot() async -> AssistantUndoSnapshot? {
        await actionStore.lastUndoSnapshot()
    }

    public func discardUndoSnapshot() async {
        await actionStore.discardUndo()
    }

    public nonisolated func interpret(
        prompt: String
    ) -> AsyncThrowingStream<AssistantInterpretEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.runInterpret(prompt: prompt, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func runInterpret(
        prompt: String,
        continuation: AsyncThrowingStream<AssistantInterpretEvent, Error>.Continuation
    ) async {
        do {
            guard await availability.availability() == .available else {
                throw CashFlowError.intelligenceUnavailable
            }
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CashFlowError.intelligence(message: "Ask to tag or categorize transactions.")
            }

            continuation.yield(.status("Understanding your request…"))

            let accounts = try await accountRepository.fetchAll()
            let tags = try await tagRepository.fetchAll()

            var intent: AssistantIntent?
            for try await event in intentInterpreting.interpret(
                prompt: trimmed,
                accounts: accounts,
                tags: tags
            ) {
                switch event {
                case .draft(let explanation, let conditionSummary):
                    continuation.yield(
                        .draft(explanation: explanation, conditionSummary: conditionSummary)
                    )
                case .intent(let resolved):
                    intent = resolved
                }
            }
            guard let intent else {
                throw CashFlowError.intelligence(message: "Couldn't interpret that request.")
            }

            continuation.yield(.status("Finding matching transactions…"))

            let proposal = try await buildProposal(
                intent: intent,
                accounts: accounts,
                tags: tags
            )
            continuation.yield(.proposal(proposal))
            continuation.finish()
        } catch let error as CashFlowError {
            continuation.finish(throwing: error)
        } catch {
            continuation.finish(
                throwing: CashFlowError.intelligence(
                    message: CashFlowError.userFacingMessage(
                        for: error,
                        fallback: "Couldn't interpret that request."
                    )
                )
            )
        }
    }

    private func buildProposal(
        intent: AssistantIntent,
        accounts: [Account],
        tags: [Tag]
    ) async throws -> AssistantProposal {
        let all = try await transactionRepository.fetchAllForCategorization()
        let pendingCount = all.filter(\.isPending).count
        let posted = all.filter { !$0.isPending }

        let probe = CategorizationRule(
            id: CategorizationRuleID("assistant-probe"),
            categoryID: intent.categoryID,
            priority: 0,
            conditions: intent.conditions,
            appliesCategory: false
        )
        let matching = posted
            .filter { CategorizationRuleMatcher.matches(probe, transaction: $0) }
            .sorted {
                if $0.postedDate != $1.postedDate {
                    return $0.postedDate > $1.postedDate
                }
                return $0.id.rawValue > $1.id.rawValue
            }

        var warnings: [String] = []
        if pendingCount > 0 {
            warnings.append("Pending transactions are excluded until they post.")
        }
        if intent.appliesCategory {
            let locked = matching.filter(\.categoryLocked).count
            if locked > 0 {
                warnings.append(
                    "\(locked) locked transaction\(locked == 1 ? "" : "s") will keep \(locked == 1 ? "its" : "their") category."
                )
            }
        }

        let existingRules = try await ruleRepository.fetchAll()
        if intent.appliesCategory {
            let shadowed = matching.filter { tx in
                let winners = CategorizationRuleMatcher.matchingRules(existingRules, transaction: tx)
                return winners.contains(where: \.appliesCategory)
            }.count
            if shadowed > 0 {
                warnings.append(
                    "\(shadowed) transaction\(shadowed == 1 ? "" : "s") already match a higher-priority categorize rule."
                )
            }
        }

        let canSaveRule = intent.appliesCategory || !intent.tagNames.isEmpty
        let saveAsRule = intent.prefersSavingRule && canSaveRule
        let conditionSummary = CategorizationConditionFormatting.summary(
            for: intent.conditions,
            accountName: { id in accounts.first(where: { $0.id == id })?.name ?? "Account" },
            tagName: { id in tags.first(where: { $0.id == id })?.name ?? "Tag" }
        )

        let samples = matching.prefix(5).map { tx in
            AssistantProposalSample(
                id: tx.id,
                title: tx.displayTitle,
                detail: sampleDetail(for: tx)
            )
        }

        let summary = buildSummary(intent: intent, count: matching.count)

        return AssistantProposal(
            summary: summary,
            conditionSummary: conditionSummary,
            affectedCount: matching.count,
            samples: Array(samples),
            saveAsRule: saveAsRule,
            warnings: warnings,
            conditions: intent.conditions,
            appliesCategory: intent.appliesCategory,
            categoryID: intent.categoryID,
            renameTitle: intent.renameTitle,
            renameLocation: intent.renameLocation,
            tagNames: intent.tagNames,
            matchingTransactionIDs: matching.map(\.id)
        )
    }

    public func execute(_ proposal: AssistantProposal) async throws -> AssistantTurn {
        await workCoordinator.beginAssistantPriority()
        do {
            let turn = try await performExecute(proposal)
            await workCoordinator.endAssistantPriority()
            return turn
        } catch {
            await workCoordinator.endAssistantPriority()
            if let cashFlow = CashFlowError.fromBridgedError(error) {
                throw cashFlow
            }
            throw CashFlowError.intelligence(
                message: CashFlowError.userFacingMessage(
                    for: error,
                    fallback: "Couldn't apply that change."
                )
            )
        }
    }

    public func undoLastChange() async throws {
        // Chat undo was removed; lasting rules undo from the rule editor.
        await actionStore.discardUndo()
    }

    private func performExecute(_ proposal: AssistantProposal) async throws -> AssistantTurn {
        let all = try await transactionRepository.fetchAllForCategorization()
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let matching = proposal.matchingTransactionIDs.compactMap { byID[$0] }
        let beforeByID = Dictionary(uniqueKeysWithValues: matching.map { ($0.id, $0) })

        let tags = try await tagRepository.fetchAll()
        let tagIDs = try await resolveTagIDs(names: proposal.tagNames, existing: tags)
        let resolved = ResolvedProposal(base: proposal, tagIDs: tagIDs)

        var savedRuleID: CategorizationRuleID?
        let canSaveRule = resolved.saveAsRule
            && (resolved.appliesCategory || !tagIDs.isEmpty)

        if canSaveRule {
            let rule = try await buildAssistantRule(from: resolved)
            let saved = try await ruleApplying.applyAndCaptureUndo(for: rule)
            savedRuleID = saved.id
            // Apply directly to the proposed matches so enriched-title matches cannot
            // diverge from what the preview counted if reapply and preview ever disagree.
            try await applyOneShot(proposal: resolved, matching: matching)
        } else {
            try await applyOneShot(proposal: resolved, matching: matching)
        }

        // Assistant renames are always one-shot (never persisted as rename rules).
        if resolved.renameTitle != nil || resolved.renameLocation != nil {
            for tx in matching {
                let title = resolved.renameTitle ?? tx.enrichedTitle ?? tx.displayTitle
                let location = resolved.renameLocation ?? tx.enrichedLocation
                let clearLocation = resolved.renameLocation.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                } ?? false
                try await transactionRepository.updateEnrichment(
                    transactionID: tx.id,
                    title: title,
                    location: location,
                    source: .user,
                    clearLocation: clearLocation
                )
            }
        }

        let afterByID = Dictionary(
            uniqueKeysWithValues: try await transactionRepository.fetchAllForCategorization()
                .map { ($0.id, $0) }
        )
        let count = beforeByID.keys.filter { id in
            guard let before = beforeByID[id], let after = afterByID[id] else { return false }
            return before.categoryID != after.categoryID
                || before.userEditedCategory != after.userEditedCategory
                || Set(before.tagIDs) != Set(after.tagIDs)
                || before.enrichedTitle != after.enrichedTitle
                || before.enrichedLocation != after.enrichedLocation
        }.count

        var lines: [String] = []
        if count == 0 && savedRuleID != nil {
            lines.append("Saved the rule.")
        } else if count > 0 {
            lines.append("Updated \(count) transaction\(count == 1 ? "" : "s").")
        } else {
            lines.append("No transactions were updated.")
        }
        if let savedRuleID, resolved.saveAsRule {
            let rules = try await ruleRepository.fetchAll()
            let name = rules.first(where: { $0.id == savedRuleID }).map {
                CategorizationConditionFormatting.summary(for: $0.conditions)
            } ?? "rule"
            lines.append("Saved rule (\(name)).")
            lines.append("Undo from Rules → Edit Rule.")
        }

        let message = AssistantMessage(
            role: .assistant,
            text: lines.map { "• \($0)" }.joined(separator: "\n")
        )
        return AssistantTurn(message: message)
    }

    private struct ResolvedProposal {
        let summary: String
        let saveAsRule: Bool
        let conditions: [CategorizationCondition]
        let appliesCategory: Bool
        let categoryID: CategoryID
        let renameTitle: String?
        let renameLocation: String?
        let tagIDs: [TagID]

        init(base: AssistantProposal, tagIDs: [TagID]) {
            summary = base.summary
            saveAsRule = base.saveAsRule
            conditions = base.conditions
            appliesCategory = base.appliesCategory
            categoryID = base.categoryID
            renameTitle = base.renameTitle
            renameLocation = base.renameLocation
            self.tagIDs = tagIDs
        }
    }

    private func applyOneShot(
        proposal: ResolvedProposal,
        matching: [Transaction]
    ) async throws {
        if proposal.appliesCategory {
            let assignments = matching.compactMap { tx -> CategoryAssignment? in
                guard !tx.categoryLocked else { return nil }
                return CategoryAssignment(
                    transactionID: tx.id,
                    categoryID: proposal.categoryID,
                    userEditedCategory: true,
                    categorySource: .user
                )
            }
            try await transactionRepository.applyCategoryAssignments(assignments)
        }
        if !proposal.tagIDs.isEmpty {
            let assignments = matching.map { tx in
                let tags = ResolveTransactionCategoryUseCase.applyingTags(
                    current: tx.tagIDs,
                    ruleTags: proposal.tagIDs,
                    suppressed: tx.suppressedTagIDs
                )
                return TagAssignment(transactionID: tx.id, tagIDs: tags)
            }
            try await transactionRepository.applyTagAssignments(assignments)
        }
    }

    private func buildAssistantRule(from proposal: ResolvedProposal) async throws -> CategorizationRule {
        let existing = try await ruleRepository.fetchAll()
        let actionsMatch: (CategorizationRule) -> Bool = { rule in
            rule.appliesCategory == proposal.appliesCategory
                && (!proposal.appliesCategory || rule.categoryID == proposal.categoryID)
                && rule.tagIDs == proposal.tagIDs
                && rule.renameTitle == nil
                && Set(rule.conditions.map(Self.conditionKey))
                    == Set(proposal.conditions.map(Self.conditionKey))
        }

        if let match = existing.first(where: actionsMatch) {
            return CategorizationRule(
                id: match.id,
                categoryID: proposal.appliesCategory ? proposal.categoryID : match.categoryID,
                priority: match.priority,
                isEnabled: true,
                conditions: proposal.conditions,
                renameTitle: nil,
                appliesCategory: proposal.appliesCategory,
                tagIDs: proposal.tagIDs,
                createdByAssistant: true
            )
        }

        let priority = (existing.map(\.priority).max() ?? -1) + 1
        return CategorizationRule(
            id: CategorizationRuleID(UUID().uuidString),
            categoryID: proposal.categoryID,
            priority: priority,
            isEnabled: true,
            conditions: proposal.conditions,
            renameTitle: nil,
            appliesCategory: proposal.appliesCategory,
            tagIDs: proposal.tagIDs,
            createdByAssistant: true
        )
    }

    private func resolveTagIDs(names: [String], existing: [Tag]) async throws -> [TagID] {
        var result: [TagID] = []
        var known = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.name.lowercased(), $0) }
        )
        for name in names {
            let key = name.lowercased()
            if let tag = known[key] {
                if !result.contains(tag.id) { result.append(tag.id) }
                continue
            }
            let created = try await tagRepository.create(name: name)
            known[key] = created
            result.append(created.id)
        }
        return result
    }

    private func buildSummary(intent: AssistantIntent, count: Int) -> String {
        var actions: [String] = []
        if intent.appliesCategory {
            actions.append("set category to \(SystemCategory.category(for: intent.categoryID).name)")
        }
        if !intent.tagNames.isEmpty {
            actions.append(
                "add tag\(intent.tagNames.count == 1 ? "" : "s") \(intent.tagNames.joined(separator: ", "))"
            )
        }
        if let rename = intent.renameTitle {
            actions.append("rename to “\(rename)”")
        }
        if let location = intent.renameLocation {
            actions.append("set location to “\(location)”")
        }
        let actionText = actions.isEmpty ? "update" : actions.joined(separator: " and ")
        return "\(actionText.prefix(1).uppercased())\(actionText.dropFirst()) for \(count) transaction\(count == 1 ? "" : "s")"
    }

    private func sampleDetail(for tx: Transaction) -> String {
        let amount = tx.amount
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = tx.currencyCode
        let amountText = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        if let location = tx.displayLocation, !location.isEmpty {
            return "\(amountText) · \(location)"
        }
        return amountText
    }

    private static func conditionKey(_ condition: CategorizationCondition) -> String {
        switch condition {
        case .titleContains(let v): return "tc:\(v.lowercased())"
        case .titleEquals(let v): return "te:\(v.lowercased())"
        case .descriptionContains(let v): return "dc:\(v.lowercased())"
        case .descriptionEquals(let v): return "de:\(v.lowercased())"
        case .locationContains(let v): return "lc:\(v.lowercased())"
        case .categoryIs(let id): return "cat:\(id.rawValue)"
        case .hasTag(let id): return "tag:\(id.rawValue)"
        case .accountID(let id): return "acct:\(id.rawValue)"
        case .amountMin(let v): return "min:\(v)"
        case .amountMax(let v): return "max:\(v)"
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26, macOS 26, *)
public typealias FoundationModelsTransactionAssistant = IntentHostTransactionAssistant
#endif

public enum TransactionAssistantFactory {
    public static func make(
        availability: any OnDeviceModelAvailabilityChecking,
        transactionRepository: any TransactionRepository,
        tagRepository: any TagRepository,
        accountRepository: any AccountRepository,
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        workCoordinator: FoundationModelsWorkCoordinator
    ) -> any TransactionAssistantServing {
        let interpreting = TransactionIntentInterpretingFactory.make(
            availability: availability,
            workCoordinator: workCoordinator
        )
        return IntentHostTransactionAssistant(
            availability: availability,
            intentInterpreting: interpreting,
            transactionRepository: transactionRepository,
            tagRepository: tagRepository,
            accountRepository: accountRepository,
            ruleRepository: ruleRepository,
            ruleApplying: ruleApplying,
            workCoordinator: workCoordinator
        )
    }
}

public enum DescriptionEnricherFactory {
    public static func make(
        availability: any OnDeviceModelAvailabilityChecking,
        workCoordinator: FoundationModelsWorkCoordinator
    ) -> any TransactionDescriptionEnriching {
        var foundation: (any TransactionDescriptionEnriching)?
        if #available(iOS 26, macOS 26, *) {
            #if canImport(FoundationModels)
            foundation = FoundationModelsDescriptionEnricher(workCoordinator: workCoordinator)
            #endif
        }
        return CompositeTransactionDescriptionEnricher(
            availability: availability,
            foundation: foundation,
            workCoordinator: workCoordinator
        )
    }
}

public enum CategoryEnricherFactory {
    public static func make(
        availability: any OnDeviceModelAvailabilityChecking,
        workCoordinator: FoundationModelsWorkCoordinator
    ) -> any TransactionCategoryEnriching {
        var foundation: (any TransactionCategoryEnriching)?
        if #available(iOS 26, macOS 26, *) {
            #if canImport(FoundationModels)
            foundation = FoundationModelsCategoryEnricher(workCoordinator: workCoordinator)
            #endif
        }
        return CompositeTransactionCategoryEnricher(
            availability: availability,
            foundation: foundation,
            workCoordinator: workCoordinator
        )
    }
}
