import Foundation
import Observation
import CashFlowKit

enum RuleEditorTab: String, CaseIterable, Identifiable {
    case categorize
    case rename

    var id: String { rawValue }

    var title: String {
        switch self {
        case .categorize: "Categorize"
        case .rename: "Rename"
        }
    }
}

struct EditableCondition: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable, Hashable {
        case titleContains
        case titleEquals
        case descriptionContains
        case descriptionEquals
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
    var amountText: String

    init(
        id: UUID = UUID(),
        kind: Kind = .titleContains,
        textValue: String = "",
        accountID: AccountID? = nil,
        amountText: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.textValue = textValue
        self.accountID = accountID
        self.amountText = amountText
    }

    init(condition: CategorizationCondition) {
        self.id = UUID()
        switch condition {
        case .titleContains(let value):
            self.kind = .titleContains
            self.textValue = value
            self.accountID = nil
            self.amountText = ""
        case .titleEquals(let value):
            self.kind = .titleEquals
            self.textValue = value
            self.accountID = nil
            self.amountText = ""
        case .descriptionContains(let value):
            self.kind = .descriptionContains
            self.textValue = value
            self.accountID = nil
            self.amountText = ""
        case .descriptionEquals(let value):
            self.kind = .descriptionEquals
            self.textValue = value
            self.accountID = nil
            self.amountText = ""
        case .accountID(let id):
            self.kind = .account
            self.textValue = ""
            self.accountID = id
            self.amountText = ""
        case .amountMin(let min):
            self.kind = .amountMin
            self.textValue = ""
            self.accountID = nil
            self.amountText = Self.currencyString(min)
        case .amountMax(let max):
            self.kind = .amountMax
            self.textValue = ""
            self.accountID = nil
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
    private let existingID: CategorizationRuleID?
    private let existingPriority: Int?

    var selectedTab: RuleEditorTab
    var categoryID: CategoryID
    var renameTitle = ""
    var isEnabled: Bool
    var conditions: [EditableCondition]
    var accounts: [Account] = []
    var isSaving = false
    var errorMessage: String?
    var didSave = false
    var showDeleteConfirmation = false

    var canSave: Bool {
        guard !isSaving, conditions.contains(where: { $0.toCondition() != nil }) else {
            return false
        }
        switch selectedTab {
        case .categorize:
            return true
        case .rename:
            return !renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var canDelete: Bool {
        existingID != nil && !isSaving
    }

    var navigationTitle: String {
        existingID == nil ? "New Rule" : "Edit Rule"
    }

    init(
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        accountRepository: any AccountRepository,
        existing: CategorizationRule? = nil,
        prefillTitle: String? = nil,
        prefillCategoryID: CategoryID? = nil
    ) {
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.accountRepository = accountRepository
        if let existing {
            self.existingID = existing.id
            self.existingPriority = existing.priority
            self.categoryID = existing.categoryID
            self.renameTitle = existing.renameTitle ?? ""
            self.isEnabled = existing.isEnabled
            self.conditions = existing.conditions.map(EditableCondition.init(condition:))
            self.selectedTab = (!existing.appliesCategory && existing.renameTitle != nil)
                ? .rename
                : .categorize
        } else {
            self.existingID = nil
            self.existingPriority = nil
            self.categoryID = prefillCategoryID ?? SystemCategory.other.id
            self.renameTitle = ""
            self.isEnabled = true
            self.selectedTab = .categorize
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
            accounts = try await accountRepository.fetchAll()
            if conditions.contains(where: { $0.kind == .account && $0.accountID == nil }),
               let first = accounts.first
            {
                for index in conditions.indices where conditions[index].kind == .account
                    && conditions[index].accountID == nil
                {
                    conditions[index].accountID = first.id
                }
            }
        } catch {
            errorMessage = "Couldn't load accounts."
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
        guard let existingID, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await ruleRepository.delete(id: existingID)
            _ = try await ruleApplying.reapplyAllRules()
            didSave = true
        } catch {
            errorMessage = "Couldn't delete rule."
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

            let rule: CategorizationRule
            switch selectedTab {
            case .categorize:
                rule = CategorizationRule(
                    id: existingID ?? CategorizationRuleID(UUID().uuidString),
                    categoryID: categoryID,
                    priority: priority,
                    isEnabled: isEnabled,
                    conditions: built,
                    renameTitle: nil,
                    appliesCategory: true
                )
            case .rename:
                rule = CategorizationRule(
                    id: existingID ?? CategorizationRuleID(UUID().uuidString),
                    categoryID: categoryID,
                    priority: priority,
                    isEnabled: isEnabled,
                    conditions: built,
                    renameTitle: renameTitle,
                    appliesCategory: false
                )
            }

            try await ruleRepository.upsert(rule)
            _ = try await ruleApplying.reapplyAllRules()
            didSave = true
        } catch {
            errorMessage = "Couldn't save rule."
        }
    }
}
