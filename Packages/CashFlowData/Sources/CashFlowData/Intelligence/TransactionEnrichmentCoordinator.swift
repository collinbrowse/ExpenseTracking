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

    public func enrichAfterSync() async {
        guard !isRunning else { return }
        guard await availability.availability() == .available else { return }
        isRunning = true
        defer { isRunning = false }

        await enrichDescriptions()
        guard !(await workCoordinator.isAssistantPriorityActive) else { return }
        await enrichCategories()
    }

    private func enrichDescriptions() async {
        do {
            let needing = try await transactionRepository.fetchNeedingEnrichment(
                limit: Self.descriptionBatchLimit
            )
            for transaction in needing {
                if await workCoordinator.isAssistantPriorityActive { return }
                let parsed = await descriptionEnricher.enrich(
                    rawDescription: transaction.description
                )
                let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                try await transactionRepository.updateEnrichment(
                    transactionID: transaction.id,
                    title: title,
                    location: parsed.location
                )
            }
        } catch {
            // Best-effort; sync already succeeded.
        }
    }

    private func enrichCategories() async {
        do {
            let rules = try await ruleRepository.fetchAll()
            let candidates = try await transactionRepository.fetchAllForCategorization()
            var assignments: [CategoryAssignment] = []
            assignments.reserveCapacity(Self.categoryBatchLimit)

            for transaction in candidates {
                if await workCoordinator.isAssistantPriorityActive { break }
                guard assignments.count < Self.categoryBatchLimit else { break }
                guard !transaction.categoryLocked else { continue }
                guard !transaction.userEditedCategory else { continue }

                let matching = CategorizationRuleMatcher.matchingRules(
                    rules,
                    transaction: transaction
                )
                if matching.contains(where: \.appliesCategory) {
                    continue
                }

                let haystack = transaction.enrichedTitle ?? transaction.displayTitle
                guard let suggested = await categoryEnricher.suggestCategory(
                    description: haystack,
                    amount: transaction.amount
                ) else {
                    continue
                }
                guard suggested != transaction.categoryID else { continue }
                guard transaction.categoryID == SystemCategory.other.id else { continue }

                assignments.append(
                    CategoryAssignment(
                        transactionID: transaction.id,
                        categoryID: suggested,
                        userEditedCategory: false
                    )
                )
            }

            try await transactionRepository.applyCategoryAssignments(assignments)
        } catch {
            // Best-effort.
        }
    }
}

/// No-op runner for tests / AI-unavailable hosts that still need a conforming value.
public struct NoOpTransactionEnrichmentRunner: TransactionEnrichmentRunning {
    public init() {}
    public func enrichAfterSync() async {}
}
