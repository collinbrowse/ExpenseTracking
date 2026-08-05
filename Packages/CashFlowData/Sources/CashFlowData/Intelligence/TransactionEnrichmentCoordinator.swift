import Foundation
import CashFlowKit

/// Post-sync enrichment: merchant/location cache, then optional LLM categories.
public actor TransactionEnrichmentCoordinator: TransactionEnrichmentRunning {
    public static let descriptionBatchLimit = 12
    public static let categoryBatchLimit = 12

    private let availability: any OnDeviceModelAvailabilityChecking
    private let descriptionEnricher: any TransactionDescriptionEnriching
    private let categoryEnricher: any TransactionCategoryEnriching
    private let transactionRepository: any TransactionRepository
    private let ruleRepository: any CategorizationRuleRepository
    private let workCoordinator: FoundationModelsWorkCoordinator
    private var isRunning = false

    public init(
        availability: any OnDeviceModelAvailabilityChecking,
        descriptionEnricher: any TransactionDescriptionEnriching,
        categoryEnricher: any TransactionCategoryEnriching,
        transactionRepository: any TransactionRepository,
        ruleRepository: any CategorizationRuleRepository,
        workCoordinator: FoundationModelsWorkCoordinator = .shared
    ) {
        self.availability = availability
        self.descriptionEnricher = descriptionEnricher
        self.categoryEnricher = categoryEnricher
        self.transactionRepository = transactionRepository
        self.ruleRepository = ruleRepository
        self.workCoordinator = workCoordinator
    }

    public func enrichAfterSync(
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async {
        guard !isRunning else { return }
        guard await availability.availability() == .available else { return }
        isRunning = true
        defer { isRunning = false }

        let needing: [Transaction]
        do {
            needing = try await transactionRepository.fetchNeedingEnrichment(
                limit: Self.descriptionBatchLimit
            )
        } catch {
            return
        }

        let categoryTargets: [Transaction]
        if await workCoordinator.isAssistantPriorityActive {
            categoryTargets = []
        } else {
            categoryTargets = (try? await categoryTargetsNeedingSuggestion()) ?? []
        }

        let total = needing.count + categoryTargets.count
        guard total > 0 else { return }

        var completed = 0
        onProgress?(completed, total)

        for transaction in needing {
            if await workCoordinator.isAssistantPriorityActive { return }
            let parsed = await descriptionEnricher.enrich(
                rawDescription: transaction.description
            )
            let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                try? await transactionRepository.updateEnrichment(
                    transactionID: transaction.id,
                    title: title,
                    location: parsed.location
                )
            }
            completed += 1
            onProgress?(completed, total)
        }

        guard !(await workCoordinator.isAssistantPriorityActive) else { return }
        guard !categoryTargets.isEmpty else { return }

        var assignments: [CategoryAssignment] = []
        assignments.reserveCapacity(categoryTargets.count)

        for transaction in categoryTargets {
            if await workCoordinator.isAssistantPriorityActive { break }
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
            onProgress?(completed, total)
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
    public func enrichAfterSync(
        onProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async {
        _ = onProgress
    }
}
