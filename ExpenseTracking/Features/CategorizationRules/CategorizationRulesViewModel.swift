import Foundation
import Observation
import CashFlowKit

@MainActor
@Observable
final class CategorizationRulesViewModel {
    let ruleRepository: any CategorizationRuleRepository
    let ruleApplying: any CategorizationRuleApplying
    let accountRepository: any AccountRepository
    let tagRepository: any TagRepository
    let ruleDrafting: (any CategorizationRuleDrafting)?
    let availabilityChecker: (any OnDeviceModelAvailabilityChecking)?

    var rules: [CategorizationRule] = []
    var accounts: [Account] = []
    var tags: [Tag] = []
    var bannerMessage: String?
    var isBusy = false
    var editorRoute: EditorRoute?

    enum EditorRoute: Identifiable, Hashable {
        case create
        case edit(CategorizationRuleID)
        case createFromTransaction(title: String, categoryID: CategoryID)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let id): "edit-\(id.rawValue)"
            case .createFromTransaction(let title, let categoryID):
                "from-\(title)-\(categoryID.rawValue)"
            }
        }
    }

    init(
        ruleRepository: any CategorizationRuleRepository,
        ruleApplying: any CategorizationRuleApplying,
        accountRepository: any AccountRepository,
        tagRepository: any TagRepository,
        ruleDrafting: (any CategorizationRuleDrafting)? = nil,
        availabilityChecker: (any OnDeviceModelAvailabilityChecking)? = nil
    ) {
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.accountRepository = accountRepository
        self.tagRepository = tagRepository
        self.ruleDrafting = ruleDrafting
        self.availabilityChecker = availabilityChecker
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        do {
            async let loadedRules = ruleRepository.fetchAll()
            async let loadedAccounts = accountRepository.fetchAll()
            async let loadedTags = tagRepository.fetchAll()
            rules = try await loadedRules
            accounts = try await loadedAccounts
            tags = try await loadedTags
            bannerMessage = nil
        } catch {
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't load rules."
            )
        }
    }

    func accountName(for id: AccountID) -> String {
        accounts.first(where: { $0.id == id })?.name ?? "Account"
    }

    func tagName(for id: TagID) -> String {
        tags.first(where: { $0.id == id })?.name ?? "Tag"
    }

    func summary(for rule: CategorizationRule) -> String {
        CategorizationRuleFormatting.summary(
            for: rule,
            accountName: { [self] in accountName(for: $0) },
            tagName: { [self] in tagName(for: $0) }
        )
    }

    func setEnabled(_ rule: CategorizationRule, isEnabled: Bool) async {
        guard rule.isEnabled != isEnabled else { return }
        let updated = CategorizationRule(
            id: rule.id,
            categoryID: rule.categoryID,
            priority: rule.priority,
            isEnabled: isEnabled,
            conditions: rule.conditions,
            renameTitle: rule.renameTitle,
            appliesCategory: rule.appliesCategory,
            tagIDs: rule.tagIDs,
            createdByAssistant: rule.createdByAssistant,
            applySnapshot: rule.applySnapshot
        )
        isBusy = true
        defer { isBusy = false }
        do {
            if isEnabled {
                _ = try await ruleApplying.applyAndCaptureUndo(for: updated)
            } else {
                try await ruleRepository.upsert(updated)
                _ = try await ruleApplying.reapplyAllRules()
            }
            await reload()
        } catch {
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't update rule."
            )
        }
    }

    func delete(_ rule: CategorizationRule) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await ruleRepository.delete(id: rule.id)
            _ = try await ruleApplying.reapplyAllRules()
            await reload()
        } catch {
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't delete rule."
            )
        }
    }

    func move(from source: IndexSet, to destination: Int) async {
        var ordered = rules
        ordered.move(fromOffsets: source, toOffset: destination)
        isBusy = true
        defer { isBusy = false }
        do {
            try await ruleRepository.reorder(ids: ordered.map(\.id))
            _ = try await ruleApplying.reapplyAllRules()
            await reload()
        } catch {
            bannerMessage = CashFlowError.userFacingMessage(
                for: error,
                fallback: "Couldn't reorder rules."
            )
        }
    }

}
