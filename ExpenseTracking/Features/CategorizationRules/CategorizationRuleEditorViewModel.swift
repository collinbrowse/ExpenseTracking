import Foundation
import Observation
import CashFlowKit

struct EditableCondition: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case titleContains
        case titleEquals
        case descriptionContains
        case descriptionEquals
        case locationContains
        case categoryIs
        case hasTag
        case account
        case amountMin
        case amountMax

        var id: String { rawValue }

        var label: String {
            switch self {
            case .titleContains: "Title contains"
            case .titleEquals: "Title is"
            case .descriptionContains: "Description contains"
            case .descriptionEquals: "Description is"
            case .locationContains: "Location contains"
            case .categoryIs: "Category is"
            case .hasTag: "Has tag"
            case .account: "Account is"
            case .amountMin: "Amount at least"
            case .amountMax: "Amount at most"
            }
        }
    }

    var id: UUID
    var kind: Kind
    var textValue: String
    var accountID: AccountID?
    var categoryID: CategoryID?
    var tagID: TagID?
    var amountText: String

    init(
        id: UUID = UUID(),
        kind: Kind = .titleContains,
        textValue: String = "",
        accountID: AccountID? = nil,
        categoryID: CategoryID? = nil,
        tagID: TagID? = nil,
        amountText: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.textValue = textValue
        self.accountID = accountID
        self.categoryID = categoryID
        self.tagID = tagID
        self.amountText = amountText
    }

    init(condition: CategorizationCondition) {
        self.id = UUID()
        switch condition {
        case .titleContains(let value):
            self.kind = .titleContains
            self.textValue = value
            self.accountID = nil
            self.categoryID = nil
            self.tagID = nil
            self.amountText = ""
        case .titleEquals(let value):
            self.kind = .titleEquals
            self.textValue = value
            self.accountID = nil
            self.categoryID = nil
            self.tagID = nil
            self.amountText = ""
        case .descriptionContains(let value):
            self.kind = .descriptionContains
            self.textValue = value
            self.accountID = nil
            self.categoryID = nil
            self.tagID = nil
            self.amountText = ""
        case .descriptionEquals(let value):
            self.kind = .descriptionEquals
            self.textValue = value
            self.accountID = nil
            self.categoryID = nil
            self.tagID = nil
            self.amountText = ""
        case .locationContains(let value):
            self.kind = .locationContains
            self.textValue = value
            self.accountID = nil
            self.categoryID = nil
            self.tagID = nil
            self.amountText = ""
        case .categoryIs(let id):
            self.kind = .categoryIs
            self.textValue = ""
            self.accountID = nil
            self.categoryID = id
            self.tagID = nil
            self.amountText = ""
        case .hasTag(let id):
            self.kind = .hasTag
            self.textValue = ""
            self.accountID = nil
            self.categoryID = nil
            self.tagID = id
            self.amountText = ""
        case .accountID(let id):
            self.kind = .account
            self.textValue = ""
            self.accountID = id
            self.categoryID = nil
            self.tagID = nil
            self.amountText = ""
        case .amountMin(let min):
            self.kind = .amountMin
            self.textValue = ""
            self.accountID = nil
            self.categoryID = nil
            self.tagID = nil
            self.amountText = Self.currencyString(min)
        case .amountMax(let max):
            self.kind = .amountMax
            self.textValue = ""
            self.accountID = nil
            self.categoryID = nil
            self.tagID = nil
            self.amountText = Self.currencyString(max)
        }
    }

    func toCondition() -> CategorizationCondition? {
        switch kind {
        case .titleContains:
            let trimmed = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .titleContains(trimmed)
        case .titleEquals:
            let trimmed = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .titleEquals(trimmed)
        case .descriptionContains:
            let trimmed = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .descriptionContains(trimmed)
        case .descriptionEquals:
            let trimmed = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .descriptionEquals(trimmed)
        case .locationContains:
            let trimmed = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .locationContains(trimmed)
        case .categoryIs:
            guard let categoryID else { return nil }
            return .categoryIs(categoryID)
        case .hasTag:
            guard let tagID else { return nil }
            return .hasTag(tagID)
        case .account:
            guard let accountID else { return nil }
            return .accountID(accountID)
        case .amountMin:
            guard let amount = Self.parseDecimal(amountText) else { return nil }
            return .amountMin(amount)
        case .amountMax:
            guard let amount = Self.parseDecimal(amountText) else { return nil }
            return .amountMax(amount)
        }
    }

    /// Formats the amount field as USD when it contains a parseable number.
    mutating func formatAmountAsCurrency() {
        guard kind == .amountMin || kind == .amountMax else { return }
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let amount = Self.parseDecimal(trimmed) else { return }
        amountText = Self.currencyString(amount)
    }

    static func currencyString(_ value: Decimal) -> String {
        CurrencyFormatting.usd(value)
    }

    static func parseDecimal(_ text: String) -> Decimal? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }
}

@MainActor
@Observable
final class CategorizationRuleEditorViewModel {
    private let ruleRepository: any CategorizationRuleRepository
    private let ruleApplying: any CategorizationRuleApplying
    private let accountRepository: any AccountRepository
    private let tagRepository: any TagRepository
    private let ruleDrafting: (any CategorizationRuleDrafting)?
    private let availabilityChecker: (any OnDeviceModelAvailabilityChecking)?
    private let existingID: CategorizationRuleID?
    private let existingPriority: Int?
    private let createdByAssistant: Bool
    private let existingApplySnapshot: CategorizationRuleApplySnapshot?

    var appliesCategory: Bool
    var categoryID: CategoryID
    var appliesRename: Bool
    var renameTitle = ""
    var selectedTagIDs: Set<TagID> = []
    var isEnabled: Bool
    var conditions: [EditableCondition]
    var accounts: [Account] = []
    var tags: [Tag] = []
    var isSaving = false
    var isUndoing = false
    var errorMessage: String?
    var didSave = false
    var showDeleteConfirmation = false
    var showUndoConfirmation = false
    var canUndoApply: Bool
    /// Natural-language composer is hidden until the user opts in.
    var showNaturalLanguageEditor = false

    /// Natural-language prompt used only to fill the same editor fields.
    var assistantPrompt = ""
    var isDrafting = false
    var assistantAvailability: OnDeviceModelAvailability = .unavailable
    var assistantBanner: String?

    var canUseAssistant: Bool {
        ruleDrafting != nil && assistantAvailability == .available
    }

    /// Shows the assistant composer when drafting is wired (even if currently unavailable).
    var ruleDraftingAvailable: Bool {
        ruleDrafting != nil
    }

    var canSave: Bool {
        guard !isSaving, conditions.contains(where: { $0.toCondition() != nil }) else {
            return false
        }
        let hasCategory = appliesCategory
        let hasRename = appliesRename && !renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTags = !selectedTagIDs.isEmpty
        return hasCategory || hasRename || hasTags
    }

    var canDelete: Bool {
        existingID != nil && !isSaving
    }

    var navigationTitle: String {
        existingID == nil ? "New Rule" : "Edit Rule"
    }

    var showsAssistantBadge: Bool {
        createdByAssistant
    }

    var canUndo: Bool {
        canUndoApply && !isSaving && !isUndoing
    }

    init(
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        accountRepository: any AccountRepository,
        tagRepository: any TagRepository,
        ruleDrafting: (any CategorizationRuleDrafting)? = nil,
        availabilityChecker: (any OnDeviceModelAvailabilityChecking)? = nil,
        existing: CategorizationRule? = nil,
        prefillTitle: String? = nil,
        prefillCategoryID: CategoryID? = nil
    ) {
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.accountRepository = accountRepository
        self.tagRepository = tagRepository
        self.ruleDrafting = ruleDrafting
        self.availabilityChecker = availabilityChecker
        if let existing {
            self.existingID = existing.id
            self.existingPriority = existing.priority
            self.createdByAssistant = existing.createdByAssistant
            self.existingApplySnapshot = existing.applySnapshot
            self.appliesCategory = existing.appliesCategory
            self.categoryID = existing.categoryID
            self.appliesRename = existing.renameTitle != nil
            self.renameTitle = existing.renameTitle ?? ""
            self.selectedTagIDs = Set(existing.tagIDs)
            self.isEnabled = existing.isEnabled
            self.canUndoApply = existing.canUndoApply
            self.conditions = existing.conditions.map(EditableCondition.init(condition:))
        } else {
            self.existingID = nil
            self.existingPriority = nil
            self.createdByAssistant = false
            self.existingApplySnapshot = nil
            self.appliesCategory = true
            self.categoryID = prefillCategoryID ?? SystemCategory.other.id
            self.appliesRename = false
            self.renameTitle = ""
            self.selectedTagIDs = []
            self.isEnabled = true
            self.canUndoApply = false
            if let prefillTitle, !prefillTitle.isEmpty {
                self.conditions = [
                    EditableCondition(kind: .titleContains, textValue: prefillTitle),
                ]
            } else {
                self.conditions = [EditableCondition()]
            }
        }
    }

    func onAppear() async {
        do {
            async let loadedAccounts = accountRepository.fetchAll()
            async let loadedTags = tagRepository.fetchAll()
            accounts = try await loadedAccounts
            tags = try await loadedTags
            if conditions.contains(where: { $0.kind == .account && $0.accountID == nil }),
               let first = accounts.first
            {
                for index in conditions.indices where conditions[index].kind == .account
                    && conditions[index].accountID == nil
                {
                    conditions[index].accountID = first.id
                }
            }
            if conditions.contains(where: { $0.kind == .categoryIs && $0.categoryID == nil }) {
                for index in conditions.indices where conditions[index].kind == .categoryIs
                    && conditions[index].categoryID == nil
                {
                    conditions[index].categoryID = SystemCategory.other.id
                }
            }
            if conditions.contains(where: { $0.kind == .hasTag && $0.tagID == nil }),
               let first = tags.first
            {
                for index in conditions.indices where conditions[index].kind == .hasTag
                    && conditions[index].tagID == nil
                {
                    conditions[index].tagID = first.id
                }
            }
        } catch {
            errorMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't load accounts."
            )
        }
        if let availabilityChecker {
            assistantAvailability = await availabilityChecker.availability()
        }
    }

    /// Fills the editor with a draft that matches the manual rule format.
    func draftFromNaturalLanguage() async {
        guard let ruleDrafting, canUseAssistant, !isDrafting else { return }
        let prompt = assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            assistantBanner = "Describe the rule you want."
            return
        }
        isDrafting = true
        assistantBanner = nil
        errorMessage = nil
        defer { isDrafting = false }

        do {
            let draft = try await ruleDrafting.draft(from: prompt, accounts: accounts)
            apply(draft: draft)
            assistantBanner = draft.explanation.isEmpty
                ? "Filled the rule from your description. Review and Save."
                : draft.explanation
        } catch {
            assistantBanner = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't draft that rule."
            )
        }
    }

    func apply(draft: CategorizationRuleDraft) {
        switch draft.action {
        case .categorize:
            appliesCategory = true
            appliesRename = false
            categoryID = draft.categoryID
            renameTitle = ""
        case .rename:
            appliesCategory = false
            appliesRename = true
            renameTitle = draft.renameTitle ?? ""
            categoryID = draft.categoryID
        }
        let mapped = draft.conditions.map(EditableCondition.init(condition:))
        conditions = mapped.isEmpty ? [EditableCondition()] : mapped
    }

    func toggleTag(_ id: TagID) {
        if selectedTagIDs.contains(id) {
            selectedTagIDs.remove(id)
        } else {
            selectedTagIDs.insert(id)
        }
    }

    func addCondition() {
        conditions.append(EditableCondition())
    }

    func removeCondition(id: UUID) {
        conditions.removeAll { $0.id == id }
        if conditions.isEmpty {
            conditions = [EditableCondition()]
        }
    }

    func formatAmountCondition(id: UUID) {
        guard let index = conditions.firstIndex(where: { $0.id == id }) else { return }
        conditions[index].formatAmountAsCurrency()
    }

    func delete() async {
        guard let existingID, !isSaving, !isUndoing else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await ruleRepository.delete(id: existingID)
            _ = try await ruleApplying.reapplyAllRules()
            didSave = true
        } catch {
            errorMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't delete rule."
            )
        }
    }

    func undoApply() async {
        guard let existingID, canUndo else { return }
        isUndoing = true
        defer { isUndoing = false }
        do {
            let restored = try await ruleApplying.undoRule(id: existingID)
            isEnabled = false
            canUndoApply = false
            assistantBanner = restored == 0
                ? "Rule turned off. No transaction changes were reverted (manual edits were kept)."
                : "Rule turned off. Reverted \(restored) transaction\(restored == 1 ? "" : "s"). Manual edits were kept."
            didSave = true
        } catch {
            errorMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't undo this rule."
            )
        }
    }

    func save() async {
        guard canSave else { return }
        let built = conditions.compactMap { $0.toCondition() }
        guard !built.isEmpty else {
            errorMessage = "Add at least one valid condition."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let priority: Int
            if let existingPriority {
                priority = existingPriority
            } else {
                let existing = try await ruleRepository.fetchAll()
                priority = (existing.map(\.priority).max() ?? -1) + 1
            }

            let rename = appliesRename
                ? renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let rule = CategorizationRule(
                id: existingID ?? CategorizationRuleID(UUID().uuidString),
                categoryID: categoryID,
                priority: priority,
                isEnabled: isEnabled,
                conditions: built,
                renameTitle: (rename?.isEmpty == false) ? rename : nil,
                appliesCategory: appliesCategory,
                tagIDs: selectedTagIDs.sorted { $0.rawValue < $1.rawValue },
                createdByAssistant: createdByAssistant,
                applySnapshot: isEnabled ? nil : existingApplySnapshot
            )

            if rule.isEnabled {
                let saved = try await ruleApplying.applyAndCaptureUndo(for: rule)
                canUndoApply = saved.canUndoApply
            } else {
                try await ruleRepository.upsert(rule)
                _ = try await ruleApplying.reapplyAllRules()
                canUndoApply = rule.canUndoApply
            }
            didSave = true
        } catch {
            errorMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't save rule."
            )
        }
    }
}
