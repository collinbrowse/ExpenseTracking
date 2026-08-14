import Foundation
import Observation
import CashFlowKit

/// Editor sheet + matching-rules orchestration carved out of the transactions list ViewModel.
@MainActor
@Observable
final class TransactionEditorSession {
    private let transactionRepository: any TransactionRepository
    private let accountRepository: any AccountRepository
    private let tagRepository: any TagRepository
    private let ruleRepository: any CategorizationRuleRepository
    private let ruleApplying: any CategorizationRuleApplying
    private let ruleDrafting: (any CategorizationRuleDrafting)?
    private let availabilityChecker: (any OnDeviceModelAvailabilityChecking)?

    var selectedTransactionID: TransactionID?
    var editingDescription = ""
    var editingCategoryID: CategoryID = SystemCategory.other.id
    var editingCategoryLocked = false
    var editingTagIDs: Set<TagID> = []
    var editingAccountName = ""
    var editingLocation = ""
    var editingAmountText = ""
    var editingAmountIsIncome = false
    var editingRawDescription = ""
    var editingIngestSource: IngestSource = .bankLink
    var newTagName = ""
    var matchingRules: [CategorizationRule] = []
    var showRuleEditor = false
    var ruleEditor: CategorizationRuleEditorViewModel?
    var isSavingEdits = false

    private var matchingRulesTask: Task<Void, Never>?

    /// List-owned caches (updated by the parent ViewModel).
    var accounts: [Account] = []
    var tags: [CashFlowKit.Tag] = []
    var accountNames: [AccountID: String] = [:]
    var tagNames: [TagID: String] = [:]

    /// Resolves the current list row for matching / save filter checks.
    var listRow: ((TransactionID) -> TransactionRowModel?)?
    /// Mutates the parent list after save / hydrate.
    var applyListRow: ((TransactionRowModel) -> Void)?
    var removeListRow: ((TransactionID) -> Void)?
    var reloadList: (() async -> Void)?
    var filterCategoryID: (() -> CategoryID?)?
    var filterTagID: (() -> TagID?)?
    var presentBanner: ((String) -> Void)?

    init(
        transactionRepository: any TransactionRepository,
        accountRepository: any AccountRepository,
        tagRepository: any TagRepository,
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        ruleDrafting: (any CategorizationRuleDrafting)? = nil,
        availabilityChecker: (any OnDeviceModelAvailabilityChecking)? = nil
    ) {
        self.transactionRepository = transactionRepository
        self.accountRepository = accountRepository
        self.tagRepository = tagRepository
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.ruleDrafting = ruleDrafting
        self.availabilityChecker = availabilityChecker
    }

    func open(for id: TransactionID) {
        selectedTransactionID = id
        newTagName = ""
        if let row = listRow?(id) {
            applyEditorFields(from: row)
        }
        Task {
            await refreshTags()
            await hydrateFromStore(id: id)
            await refreshMatchingRules()
            await reapplyIfCategoryOutOfSync(for: id)
        }
    }

    private func reapplyIfCategoryOutOfSync(for id: TransactionID) async {
        guard !editingCategoryLocked,
              let rule = matchingRules.first(where: \.appliesCategory),
              rule.categoryID != editingCategoryID
        else { return }
        do {
            _ = try await ruleApplying.reapplyAllRules()
            await hydrateFromStore(id: id)
            await refreshMatchingRules()
        } catch {
            // Leave the editor on the hydrated snapshot.
        }
    }

    private func applyEditorFields(from row: TransactionRowModel) {
        editingDescription = row.title
        editingCategoryID = row.categoryID
        editingCategoryLocked = row.categoryLocked
        editingTagIDs = Set(row.tagIDs)
        editingAccountName = row.accountName
        editingLocation = row.location ?? ""
        editingAmountText = row.amountText
        editingAmountIsIncome = row.amountIsIncome
        editingRawDescription = row.rawDescription
        editingIngestSource = row.ingestSource
    }

    private func hydrateFromStore(id: TransactionID) async {
        do {
            let transactions = try await transactionRepository.fetchAllForCategorization()
            guard let transaction = transactions.first(where: { $0.id == id }) else { return }
            let row = TransactionRowModel(
                transaction: transaction,
                accountName: accountNames[transaction.accountID]
                    ?? accounts.first(where: { $0.id == transaction.accountID })?.name
                    ?? "Account",
                tagNamesByID: tagNames
            )
            applyEditorFields(from: row)
            applyListRow?(row)
        } catch {
            // Keep the list-row snapshot already applied in open.
        }
    }

    func toggleEditingTag(_ tagID: TagID) {
        if editingTagIDs.contains(tagID) {
            editingTagIDs.remove(tagID)
        } else {
            editingTagIDs.insert(tagID)
        }
    }

    func createTagFromEditor() async {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let tag = try await tagRepository.create(name: name)
            newTagName = ""
            await refreshTags()
            if !tags.contains(where: { $0.id == tag.id }) {
                tags.append(tag)
                tags.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                tagNames[tag.id] = tag.name
            }
            editingTagIDs.insert(tag.id)
        } catch {
            presentBanner?(
                CashFlowError.userFacingMessage(for: error, fallback: "Couldn't create tag.")
            )
        }
    }

    func presentCreateRule() {
        ruleEditor = CategorizationRuleEditorViewModel(
            ruleRepository: ruleRepository,
            ruleApplying: ruleApplying,
            accountRepository: accountRepository,
            tagRepository: tagRepository,
            ruleDrafting: ruleDrafting,
            availabilityChecker: availabilityChecker,
            prefillTitle: editingDescription,
            prefillCategoryID: editingCategoryID
        )
        showRuleEditor = true
    }

    func presentEditRule(_ rule: CategorizationRule) {
        ruleEditor = CategorizationRuleEditorViewModel(
            ruleRepository: ruleRepository,
            ruleApplying: ruleApplying,
            accountRepository: accountRepository,
            tagRepository: tagRepository,
            ruleDrafting: ruleDrafting,
            availabilityChecker: availabilityChecker,
            existing: rule
        )
        showRuleEditor = true
    }

    func handleRuleEditorDismissed() async {
        let saved = ruleEditor?.didSave == true
        ruleEditor = nil
        showRuleEditor = false
        guard saved else { return }
        let editingID = selectedTransactionID
        await reloadList?()
        if let editingID, let row = listRow?(editingID) {
            editingDescription = row.title
            editingCategoryID = row.categoryID
            editingCategoryLocked = row.categoryLocked
            editingTagIDs = Set(row.tagIDs)
            editingAccountName = row.accountName
            editingLocation = row.location ?? ""
        }
        await refreshMatchingRules()
    }

    func scheduleMatchingRulesRefresh() {
        matchingRulesTask?.cancel()
        matchingRulesTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await refreshMatchingRules()
        }
    }

    func refreshMatchingRules() async {
        guard let id = selectedTransactionID,
              let row = listRow?(id)
        else {
            matchingRules = []
            return
        }
        let probe = Transaction(
            id: row.id,
            accountID: row.accountID,
            externalID: row.id.rawValue,
            amount: row.amount,
            postedDate: .now,
            description: row.rawDescription,
            categoryID: editingCategoryID,
            categoryLocked: editingCategoryLocked,
            tagIDs: Array(editingTagIDs),
            enrichedTitle: editingDescription,
            enrichedLocation: editingLocation.isEmpty ? nil : editingLocation,
            titleSource: .user
        )
        do {
            let rules = try await ruleRepository.fetchAll()
            matchingRules = CategorizationRuleMatcher.matchingRules(rules, transaction: probe)
        } catch {
            matchingRules = []
        }
    }

    func ruleSummary(for rule: CategorizationRule) -> String {
        CategorizationConditionFormatting.summary(
            for: rule.conditions,
            accountName: { [self] accountID in
                accountNames[accountID]
                    ?? accounts.first(where: { $0.id == accountID })?.name
                    ?? "Account"
            },
            tagName: { [self] tagID in
                tagNames[tagID] ?? "Tag"
            }
        )
    }

    func ruleTitle(for rule: CategorizationRule) -> String {
        if rule.appliesCategory {
            return SystemCategory.category(for: rule.categoryID).name
        }
        if let renameTitle = rule.renameTitle {
            return "Rename to “\(renameTitle)”"
        }
        return "Rename"
    }

    func ruleAppliesBadge(for rule: CategorizationRule) -> String? {
        let isWinningCategory = rule.appliesCategory
            && matchingRules.first(where: \.appliesCategory)?.id == rule.id
        let isWinningRename = rule.renameTitle != nil
            && matchingRules.first(where: { $0.renameTitle != nil })?.id == rule.id
        if isWinningCategory && isWinningRename { return "Applies" }
        if isWinningCategory { return "Category" }
        if isWinningRename { return "Rename" }
        return nil
    }

    func saveEdits() async {
        guard let id = selectedTransactionID else { return }
        let trimmedTitle = editingDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedLocation = editingLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let newCategoryID = editingCategoryID
        let locked = editingCategoryLocked
        let newTagIDs = Array(editingTagIDs).sorted { $0.rawValue < $1.rawValue }
        isSavingEdits = true
        defer { isSavingEdits = false }
        do {
            try await transactionRepository.updateCategory(
                transactionID: id,
                categoryID: newCategoryID,
                categoryLocked: locked
            )
            try await transactionRepository.updateEnrichment(
                transactionID: id,
                title: trimmedTitle,
                location: trimmedLocation.isEmpty ? nil : trimmedLocation,
                source: .user,
                clearLocation: trimmedLocation.isEmpty
            )
            try await transactionRepository.updateTags(
                transactionID: id,
                tagIDs: newTagIDs
            )
            selectedTransactionID = nil
            editingLocation = ""

            if let filterCategoryID = filterCategoryID?(), filterCategoryID != newCategoryID {
                removeListRow?(id)
                return
            }
            if let filterTagID = filterTagID?(), !newTagIDs.contains(filterTagID) {
                removeListRow?(id)
                return
            }

            if let existing = listRow?(id) {
                applyListRow?(
                    existing.replacing(
                        title: trimmedTitle,
                        location: trimmedLocation.isEmpty ? nil : trimmedLocation,
                        categoryID: newCategoryID,
                        categoryLocked: locked,
                        tagIDs: newTagIDs,
                        tagNamesByID: tagNames
                    )
                )
            }
        } catch {
            presentBanner?(
                CashFlowError.userFacingMessage(for: error, fallback: "Couldn't save changes.")
            )
        }
    }

    func refreshTags() async {
        do {
            tags = try await tagRepository.fetchAll()
            tagNames = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        } catch {
            if tags.isEmpty {
                tagNames = [:]
            }
        }
    }
}
