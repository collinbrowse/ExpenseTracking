import Foundation
import Observation
import CashFlowKit

@MainActor
@Observable
final class CategorizationRulesViewModel {
    let ruleRepository: any CategorizationRuleRepository
    let ruleApplying: any CategorizationRuleApplying
    let accountRepository: any AccountRepository

    var rules: [CategorizationRule] = []
    var accounts: [Account] = []
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
        accountRepository: any AccountRepository
    ) {
        self.ruleRepository = ruleRepository
        self.ruleApplying = ruleApplying
        self.accountRepository = accountRepository
    }

    func onAppear() async {
        await reload()
    }

    func reload() async {
        do {
            async let loadedRules = ruleRepository.fetchAll()
            async let loadedAccounts = accountRepository.fetchAll()
            rules = try await loadedRules
            accounts = try await loadedAccounts
            bannerMessage = nil
        } catch {
            bannerMessage = "Couldn't load rules."
        }
    }

    func accountName(for id: AccountID) -> String {
        accounts.first(where: { $0.id == id })?.name ?? "Account"
    }

    func summary(for rule: CategorizationRule) -> String {
        var parts = [
            CategorizationConditionFormatting.summary(for: rule.conditions) { [self] accountID in
                accountName(for: accountID)
            },
        ]
        if rule.appliesCategory {
            parts.append(SystemCategory.category(for: rule.categoryID).name)
        }
        if let renameTitle = rule.renameTitle {
            parts.append("Rename to “\(renameTitle)”")
        }
        return parts.joined(separator: " · ")
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
            appliesCategory: rule.appliesCategory
        )
        await persistAndReapply(updated)
    }

    func delete(_ rule: CategorizationRule) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await ruleRepository.delete(id: rule.id)
            _ = try await ruleApplying.reapplyAllRules()
            await reload()
        } catch {
            bannerMessage = "Couldn't delete rule."
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
            bannerMessage = "Couldn't reorder rules."
        }
    }

    private func persistAndReapply(_ rule: CategorizationRule) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await ruleRepository.upsert(rule)
            _ = try await ruleApplying.reapplyAllRules()
            await reload()
        } catch {
            bannerMessage = "Couldn't update rule."
        }
    }
}
