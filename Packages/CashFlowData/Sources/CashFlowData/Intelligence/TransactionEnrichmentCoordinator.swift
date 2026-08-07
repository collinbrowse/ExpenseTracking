import Foundation
import CashFlowKit

/// Post-sync enrichment: merchant/location cache, then initial LLM categories (Undefined backlog).
public actor TransactionEnrichmentCoordinator: TransactionEnrichmentRunning {
    public static let descriptionBatchLimit = 12
    public static let categoryBatchLimit = 12
    public static let incrementalRowBudget = 48
    public static let incrementalTimeBudgetSeconds: TimeInterval = 30
    /// Dedicated window for initial Undefined→LLM/keyword work after titles.
    public static let incrementalCategoryTimeBudgetSeconds: TimeInterval = 30
    public static let incrementalCategoryRowBudget = 24

    private let availability: any OnDeviceModelAvailabilityChecking
    private let descriptionEnricher: any TransactionDescriptionEnriching
    private let categoryEnricher: any TransactionCategoryEnriching
    private let transactionRepository: any TransactionRepository
    private let accountRepository: any AccountRepository
    private let ruleRepository: any CategorizationRuleRepository
    private let memoStore: MerchantParseMemoStore?
    private let workCoordinator: FoundationModelsWorkCoordinator
    private var isRunning = false
    private var fullDrainRunning = false

    public init(
        availability: any OnDeviceModelAvailabilityChecking,
        descriptionEnricher: any TransactionDescriptionEnriching,
        categoryEnricher: any TransactionCategoryEnriching,
        transactionRepository: any TransactionRepository,
        accountRepository: any AccountRepository,
        ruleRepository: any CategorizationRuleRepository,
        memoStore: MerchantParseMemoStore? = nil,
        workCoordinator: FoundationModelsWorkCoordinator
    ) {
        self.availability = availability
        self.descriptionEnricher = descriptionEnricher
        self.categoryEnricher = categoryEnricher
        self.transactionRepository = transactionRepository
        self.accountRepository = accountRepository
        self.ruleRepository = ruleRepository
        self.memoStore = memoStore
        self.workCoordinator = workCoordinator
    }

    public var isFullDrainRunning: Bool { fullDrainRunning }

    public func enrichAfterSync(
        skipIfLargeBacklog: Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> EnrichmentWorkEstimate? {
        guard !fullDrainRunning else { return nil }

        let untitled = (try? await transactionRepository.countNeedingEnrichment()) ?? 0
        let distinct = (try? await transactionRepository.countDistinctDescriptionsNeedingEnrichment()) ?? 0
        let undefined = (try? await transactionRepository.countNeedingCategorySuggestion()) ?? 0
        let estimate = EnrichmentWorkEstimate(
            untitledCount: untitled,
            distinctMerchantLookups: distinct,
            undefinedCount: undefined
        )
        if skipIfLargeBacklog, estimate.shouldPrompt {
            return estimate
        }
        guard untitled > 0 || undefined > 0 else { return nil }

        let availabilityState = await availability.availability()
        let assetsUnavailable = await workCoordinator.isAssetsUnavailable
        let modelsAvailable = availabilityState == .available && !assetsUnavailable
        // Category keyword fallback still runs when models are unavailable; LLM needs availability.
        if untitled > 0, !modelsAvailable {
            // Still try keyword categorization for Undefined rows.
            await enrichCategories(
                unlimited: false,
                started: Date(),
                timeBudgetSeconds: Self.incrementalCategoryTimeBudgetSeconds,
                rowsBudgetRemaining: Self.incrementalCategoryRowBudget,
                onProgress: onProgress,
                completedSoFar: 0,
                forceKeywordOnly: true
            )
            return nil
        }
        if untitled == 0, !modelsAvailable {
            await enrichCategories(
                unlimited: false,
                started: Date(),
                timeBudgetSeconds: Self.incrementalCategoryTimeBudgetSeconds,
                rowsBudgetRemaining: Self.incrementalCategoryRowBudget,
                onProgress: onProgress,
                completedSoFar: 0,
                forceKeywordOnly: true
            )
            return nil
        }

        _ = await drain(
            unlimited: false,
            shouldContinue: { true },
            onProgress: onProgress,
            onPhase: nil
        )
        return nil
    }

    public func drainAllNeedingEnrichment(
        shouldContinue: @escaping @Sendable () -> Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> EnrichmentDrainOutcome {
        guard !fullDrainRunning else { return .interrupted }
        fullDrainRunning = true
        defer { fullDrainRunning = false }
        await workCoordinator.clearAssetsUnavailableCooldown()
        _ = await workCoordinator.waitOutRateLimitPauseIfNeeded()
        return await drain(
            unlimited: true,
            shouldContinue: shouldContinue,
            onProgress: onProgress,
            onPhase: nil
        )
    }

    public func drainAllNeedingEnrichment(
        shouldContinue: @escaping @Sendable () -> Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?,
        onPhase: (@Sendable (_ phase: EnrichmentProgress.Phase, _ detail: String?) -> Void)?
    ) async -> EnrichmentDrainOutcome {
        guard !fullDrainRunning else { return .interrupted }
        fullDrainRunning = true
        defer { fullDrainRunning = false }
        await workCoordinator.clearAssetsUnavailableCooldown()
        _ = await workCoordinator.waitOutRateLimitPauseIfNeeded()
        return await drain(
            unlimited: true,
            shouldContinue: shouldContinue,
            onProgress: onProgress,
            onPhase: onPhase
        )
    }

    private func drain(
        unlimited: Bool,
        shouldContinue: @escaping @Sendable () -> Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?,
        onPhase: (@Sendable (_ phase: EnrichmentProgress.Phase, _ detail: String?) -> Void)?
    ) async -> EnrichmentDrainOutcome {
        guard !isRunning else { return .interrupted }
        isRunning = true
        defer { isRunning = false }

        let availabilityState = await availability.availability()
        let assetsUnavailable = await workCoordinator.isAssetsUnavailable
        let modelsAvailable = availabilityState == .available && !assetsUnavailable
        // Full Settings drain without models still applies keyword categories.
        if !modelsAvailable {
            let started = Date()
            await enrichCategories(
                unlimited: unlimited,
                started: Date(),
                timeBudgetSeconds: unlimited ? .infinity : Self.incrementalCategoryTimeBudgetSeconds,
                rowsBudgetRemaining: unlimited ? Int.max : Self.incrementalCategoryRowBudget,
                onProgress: onProgress,
                completedSoFar: 0,
                forceKeywordOnly: true
            )
            return .completed
        }

        let started = Date()
        var completed = 0
        var rowsThisRun = 0
        var stuckIDs = Set<TransactionID>()

        while shouldContinue() {
            if await workCoordinator.isAssistantPriorityActive { return .interrupted }
            if !unlimited {
                if rowsThisRun >= Self.incrementalRowBudget { break }
                if Date().timeIntervalSince(started) >= Self.incrementalTimeBudgetSeconds {
                    break
                }
            }

            let fetched: [Transaction]
            do {
                fetched = try await transactionRepository.fetchNeedingEnrichment(
                    limit: Self.descriptionBatchLimit + stuckIDs.count
                )
            } catch {
                return .interrupted
            }
            let needing = fetched.filter { !stuckIDs.contains($0.id) }
            guard !needing.isEmpty else { break }

            var remaining = (try? await transactionRepository.countNeedingEnrichment())
                ?? needing.count
            remaining = max(remaining - stuckIDs.count, needing.count)
            let undefinedRemaining =
                (try? await transactionRepository.countNeedingCategorySuggestion()) ?? 0
            let total = completed + remaining + undefinedRemaining
            onProgress?(completed, total)

            for transaction in needing {
                if !shouldContinue() { return .interrupted }
                if await workCoordinator.isAssistantPriorityActive { return .interrupted }
                if await workCoordinator.isAssetsUnavailable { return .interrupted }
                if !unlimited, rowsThisRun >= Self.incrementalRowBudget { break }

                let attempt = await enrichDescription(
                    transaction.description,
                    shouldContinue: shouldContinue,
                    progressSnapshot: { (completed, total) },
                    onProgress: onProgress,
                    onPhase: onPhase
                )
                if await workCoordinator.isAssetsUnavailable { return .interrupted }
                if !shouldContinue() {
                    return attempt.exhaustedByRateLimit
                        ? .interruptedByRateLimit
                        : .interrupted
                }

                let title = attempt.parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    do {
                        try await transactionRepository.updateEnrichment(
                            transactionID: transaction.id,
                            title: title,
                            location: attempt.parsed.location,
                            source: .llm,
                            clearLocation: false
                        )
                    } catch {
                        stuckIDs.insert(transaction.id)
                    }
                } else if attempt.exhaustedByRateLimit {
                    return .interruptedByRateLimit
                } else {
                    do {
                        try await transactionRepository.markEnrichmentSkipped(
                            transactionID: transaction.id
                        )
                    } catch {
                        stuckIDs.insert(transaction.id)
                    }
                }
                completed += 1
                rowsThisRun += 1
                remaining = max(remaining - 1, 0)
                onProgress?(completed, completed + remaining + undefinedRemaining)
                onPhase?(.running, nil)
            }
        }

        guard !(await workCoordinator.isAssistantPriorityActive) else { return .interrupted }

        // Category pass gets its own time/row budget so title work cannot starve Undefined rows.
        let categoryBudget: Int
        if unlimited {
            categoryBudget = Int.max
        } else {
            categoryBudget = Self.incrementalCategoryRowBudget
        }
        let forceKeyword = assetsUnavailable || availabilityState != .available
        await enrichCategories(
            unlimited: unlimited,
            started: Date(),
            timeBudgetSeconds: unlimited ? .infinity : Self.incrementalCategoryTimeBudgetSeconds,
            rowsBudgetRemaining: categoryBudget,
            onProgress: onProgress,
            completedSoFar: completed,
            forceKeywordOnly: forceKeyword
        )
        if unlimited {
            await workCoordinator.clearRateLimitPause()
        }
        return .completed
    }

    private struct DescriptionEnrichmentAttempt: Sendable {
        var parsed: ParsedTransactionDescription
        var exhaustedByRateLimit: Bool
    }

    private func enrichDescription(
        _ raw: String,
        shouldContinue: @escaping @Sendable () -> Bool,
        progressSnapshot: @escaping () -> (Int, Int),
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?,
        onPhase: (@Sendable (_ phase: EnrichmentProgress.Phase, _ detail: String?) -> Void)?
    ) async -> DescriptionEnrichmentAttempt {
        if let memoStore, let hit = try? await memoStore.lookup(rawDescription: raw),
           !hit.title.isEmpty
        {
            return DescriptionEnrichmentAttempt(parsed: hit, exhaustedByRateLimit: false)
        }

        var sawRateLimit = false
        for _ in 0..<8 {
            guard shouldContinue() else {
                return DescriptionEnrichmentAttempt(
                    parsed: ParsedTransactionDescription(title: "", location: nil, raw: raw),
                    exhaustedByRateLimit: sawRateLimit
                )
            }
            await workCoordinator.paceBeforeModelRequest()
            let parsed = await descriptionEnricher.enrich(rawDescription: raw)
            if !parsed.title.isEmpty {
                if let memoStore {
                    try? await memoStore.store(parsed)
                }
                return DescriptionEnrichmentAttempt(parsed: parsed, exhaustedByRateLimit: false)
            }
            guard await workCoordinator.isRateLimitPaused else {
                return DescriptionEnrichmentAttempt(parsed: parsed, exhaustedByRateLimit: false)
            }
            sawRateLimit = true
            let snapshot = progressSnapshot()
            onProgress?(snapshot.0, snapshot.1)
            onPhase?(
                .coolingDown,
                "Apple Intelligence is cooling down — waiting to continue…"
            )
            _ = await workCoordinator.waitOutRateLimitPauseIfNeeded()
            onPhase?(.running, nil)
        }
        return DescriptionEnrichmentAttempt(
            parsed: ParsedTransactionDescription(title: "", location: nil, raw: raw),
            exhaustedByRateLimit: sawRateLimit
        )
    }

    private func enrichCategories(
        unlimited: Bool,
        started: Date,
        timeBudgetSeconds: TimeInterval,
        rowsBudgetRemaining: Int,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?,
        completedSoFar: Int,
        forceKeywordOnly: Bool
    ) async {
        let accounts = (try? await accountRepository.fetchAll()) ?? []
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let rules = (try? await ruleRepository.fetchAll()) ?? []

        var completed = completedSoFar
        var rowsUsed = 0
        var skippedIDs = Set<TransactionID>()

        while rowsUsed < rowsBudgetRemaining {
            if !unlimited,
               Date().timeIntervalSince(started) >= timeBudgetSeconds
            {
                break
            }
            if await workCoordinator.isAssistantPriorityActive { break }

            let batch: [Transaction]
            do {
                let fetched = try await transactionRepository.fetchNeedingCategorySuggestion(
                    limit: Self.categoryBatchLimit + skippedIDs.count
                )
                batch = fetched.filter { !skippedIDs.contains($0.id) }
            } catch {
                return
            }
            guard !batch.isEmpty else { break }

            let stillNeeding =
                (try? await transactionRepository.countNeedingCategorySuggestion()) ?? batch.count
            var assignments: [CategoryAssignment] = []
            assignments.reserveCapacity(batch.count)

            for transaction in batch {
                if rowsUsed >= rowsBudgetRemaining { break }
                if await workCoordinator.isAssistantPriorityActive { break }

                if transaction.effectiveCategorySource == .user {
                    skippedIDs.insert(transaction.id)
                    continue
                }
                let matching = CategorizationRuleMatcher.matchingRules(
                    rules,
                    transaction: transaction
                )
                if matching.contains(where: \.appliesCategory) {
                    skippedIDs.insert(transaction.id)
                    continue
                }

                let account = accountsByID[transaction.accountID]
                let request = CategorySuggestionRequest(transaction: transaction, account: account)
                let suggested: CategoryID
                let source: CategorySource
                if forceKeywordOnly {
                    suggested = SuggestTransactionCategoryUseCase.execute(
                        description: transaction.displayTitle,
                        amount: transaction.amount
                    )
                    source = .keyword
                } else if let llm = await categoryEnricher.suggestCategory(request),
                          llm != SystemCategory.undefined.id
                {
                    suggested = llm
                    source = .llm
                } else {
                    suggested = SuggestTransactionCategoryUseCase.execute(
                        description: transaction.displayTitle,
                        amount: transaction.amount
                    )
                    source = .keyword
                }

                if suggested != SystemCategory.undefined.id {
                    assignments.append(
                        CategoryAssignment(
                            transactionID: transaction.id,
                            categoryID: suggested,
                            categorySource: source
                        )
                    )
                } else {
                    skippedIDs.insert(transaction.id)
                }

                rowsUsed += 1
                completed += 1
                let total = max(completed + max(stillNeeding - rowsUsed, 0), completed)
                onProgress?(completed, total)
            }

            if !assignments.isEmpty {
                try? await transactionRepository.applyCategoryAssignments(assignments)
            }
            // Avoid spinning forever when every remaining row was skipped.
            if assignments.isEmpty, batch.allSatisfy({ skippedIDs.contains($0.id) }) {
                break
            }
        }
    }
}

/// No-op runner for tests / AI-unavailable hosts that still need a conforming value.
public struct NoOpTransactionEnrichmentRunner: TransactionEnrichmentRunning {
    public init() {}

    public var isFullDrainRunning: Bool { false }

    public func enrichAfterSync(
        skipIfLargeBacklog: Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> EnrichmentWorkEstimate? {
        _ = skipIfLargeBacklog
        _ = onProgress
        return nil
    }

    public func drainAllNeedingEnrichment(
        shouldContinue: @escaping @Sendable () -> Bool,
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async -> EnrichmentDrainOutcome {
        _ = shouldContinue
        _ = onProgress
        return .completed
    }
}
