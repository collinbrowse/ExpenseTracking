import Foundation
import CashFlowKit

/// Post-sync enrichment: merchant/location cache, then optional LLM categories.
public actor TransactionEnrichmentCoordinator: TransactionEnrichmentRunning {
    public static let descriptionBatchLimit = 12
    public static let categoryBatchLimit = 12
    public static let incrementalRowBudget = 48
    public static let incrementalTimeBudgetSeconds: TimeInterval = 30

    private let availability: any OnDeviceModelAvailabilityChecking
    private let descriptionEnricher: any TransactionDescriptionEnriching
    private let categoryEnricher: any TransactionCategoryEnriching
    private let transactionRepository: any TransactionRepository
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
        ruleRepository: any CategorizationRuleRepository,
        memoStore: MerchantParseMemoStore? = nil,
        workCoordinator: FoundationModelsWorkCoordinator
    ) {
        self.availability = availability
        self.descriptionEnricher = descriptionEnricher
        self.categoryEnricher = categoryEnricher
        self.transactionRepository = transactionRepository
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

        // Count first so empty stores / already-titled rows never touch Foundation Models.
        let untitled = (try? await transactionRepository.countNeedingEnrichment()) ?? 0
        let distinct = (try? await transactionRepository.countDistinctDescriptionsNeedingEnrichment()) ?? 0
        let estimate = EnrichmentWorkEstimate(
            untitledCount: untitled,
            distinctMerchantLookups: distinct
        )
        if skipIfLargeBacklog, estimate.shouldPrompt {
            return estimate
        }
        guard untitled > 0 else { return nil }
        guard await availability.availability() == .available else { return nil }
        guard !(await workCoordinator.isAssetsUnavailable) else { return nil }

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
        // Explicit user/Settings drain: allow retry after a prior catalog failure.
        await workCoordinator.clearAssetsUnavailableCooldown()
        // If Apple still has us cooling down, wait here so we don't skip the first rows.
        _ = await workCoordinator.waitOutRateLimitPauseIfNeeded()
        return await drain(
            unlimited: true,
            shouldContinue: shouldContinue,
            onProgress: onProgress,
            onPhase: nil
        )
    }

    /// Full drain with phase callbacks (cooling down vs running) for Settings / Live Activity.
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
        // Claim the slot before the first `await` — actors are reentrant, so checking and
        // setting across a suspension lets two drains run concurrently against one model.
        guard !isRunning else { return .interrupted }
        isRunning = true
        defer { isRunning = false }

        guard await availability.availability() == .available else { return .interrupted }
        guard !(await workCoordinator.isAssetsUnavailable) else { return .interrupted }

        let started = Date()
        var completed = 0
        var rowsThisRun = 0
        /// Rows we could not retire because the write failed. Without this the next
        /// `fetchNeedingEnrichment` returns them again and the drain loops forever.
        var stuckIDs = Set<TransactionID>()

        while shouldContinue() {
            if await workCoordinator.isAssistantPriorityActive { return .interrupted }
            if !unlimited {
                if rowsThisRun >= Self.incrementalRowBudget { break }
                if Date().timeIntervalSince(started) >= Self.incrementalTimeBudgetSeconds {
                    return .completed
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

            // Count once per batch, then decrement locally. Counting per row was a
            // full-table scan for every transaction in the backlog.
            var remaining = (try? await transactionRepository.countNeedingEnrichment())
                ?? needing.count
            remaining = max(remaining - stuckIDs.count, needing.count)
            let total = completed + remaining
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
                    // Only pause the whole drain when THIS row hit an unresolved rate limit.
                    return .interruptedByRateLimit
                } else {
                    // Unparseable this pass — leave raw text, drop from the backlog.
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
                onProgress?(completed, completed + remaining)
                onPhase?(.running, nil)
            }
        }

        // Incremental budget exhausted — stop without category pass this round.
        if !unlimited, rowsThisRun >= Self.incrementalRowBudget {
            return .completed
        }
        guard !(await workCoordinator.isAssistantPriorityActive) else { return .interrupted }
        guard !(await workCoordinator.isAssetsUnavailable) else { return .interrupted }
        await enrichCategories(onProgress: onProgress, completedSoFar: completed)
        if unlimited {
            await workCoordinator.clearRateLimitPause()
        }
        return .completed
    }

    private struct DescriptionEnrichmentAttempt: Sendable {
        var parsed: ParsedTransactionDescription
        /// True when cool-down retries were exhausted while still rate-limited.
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
        // Retry the same merchant across rate-limit cool-downs instead of skipping it.
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
                // Empty for a non-throttle reason (unsupported language, refused parse, etc.).
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
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?,
        completedSoFar: Int
    ) async {
        let categoryTargets: [Transaction]
        do {
            categoryTargets = try await categoryTargetsNeedingSuggestion()
        } catch {
            return
        }
        guard !categoryTargets.isEmpty else { return }

        var completed = completedSoFar
        var assignments: [CategoryAssignment] = []
        assignments.reserveCapacity(categoryTargets.count)

        for transaction in categoryTargets {
            if await workCoordinator.isAssistantPriorityActive { break }
            if await workCoordinator.isAssetsUnavailable { break }
            let haystack = transaction.enrichedTitle ?? transaction.displayTitle
            if let suggested = await categoryEnricher.suggestCategory(
                description: haystack,
                amount: transaction.amount
            ),
               suggested != transaction.categoryID,
               transaction.categoryID == SystemCategory.other.id
            {
                assignments.append(
                    CategoryAssignment(
                        transactionID: transaction.id,
                        categoryID: suggested,
                        userEditedCategory: false
                    )
                )
            }
            completed += 1
            onProgress?(completed, completedSoFar + categoryTargets.count)
        }

        try? await transactionRepository.applyCategoryAssignments(assignments)
    }

    private func categoryTargetsNeedingSuggestion() async throws -> [Transaction] {
        let rules = try await ruleRepository.fetchAll()
        let candidates = try await transactionRepository.fetchAllForCategorization()
        var targets: [Transaction] = []
        targets.reserveCapacity(Self.categoryBatchLimit)

        for transaction in candidates {
            guard targets.count < Self.categoryBatchLimit else { break }
            guard !transaction.categoryLocked else { continue }
            guard !transaction.userEditedCategory else { continue }
            guard transaction.categoryID == SystemCategory.other.id else { continue }

            let matching = CategorizationRuleMatcher.matchingRules(
                rules,
                transaction: transaction
            )
            if matching.contains(where: \.appliesCategory) {
                continue
            }
            targets.append(transaction)
        }
        return targets
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
