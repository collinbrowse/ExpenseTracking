import Foundation
import CashFlowKit

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
@Generable
struct GenerableRuleCondition {
    @Guide(
        description: "Condition kind",
        .anyOf([
            "titleContains",
            "titleEquals",
            "descriptionContains",
            "descriptionEquals",
            "locationContains",
            "categoryIs",
            "account",
            "amountMin",
            "amountMax",
        ])
    )
    var kind: String

    @Guide(description: "Text for title/description/location conditions, category name, or exact account name; empty otherwise")
    var textValue: String

    @Guide(description: "Decimal amount for amountMin/amountMax without currency symbols; empty otherwise")
    var amountValue: String
}

@available(iOS 26, macOS 26, *)
@Generable
struct GenerableRuleDraft {
    @Guide(description: "Rule action", .anyOf(["categorize", "rename"]))
    var action: String

    @Guide(
        description: "System category display name when action is categorize",
        .anyOf([
            "Income",
            "Hidden",
            "Transfer",
            "Credit Card Payment",
            "Groceries",
            "Food & Dining",
            "Auto & Transport",
            "Shopping",
            "Bills & Utilities",
            "Entertainment",
            "Rent & Mortgage",
            "Travel & Vacation",
            "Health & Fitness",
            "Business Services",
            "Fees & Charges",
            "Medical",
            "Other",
        ])
    )
    var categoryName: String

    @Guide(description: "New merchant title when action is rename; empty for categorize")
    var renameTitle: String

    @Guide(description: "AND conditions that must all match", .maximumCount(6))
    var conditions: [GenerableRuleCondition]

    @Guide(description: "Short explanation of the draft for the user")
    var explanation: String
}

@available(iOS 26, macOS 26, *)
public struct FoundationModelsRuleDrafting: CategorizationRuleDrafting {
    private let availability: any OnDeviceModelAvailabilityChecking
    private let workCoordinator: FoundationModelsWorkCoordinator

    public init(
        availability: any OnDeviceModelAvailabilityChecking,
        workCoordinator: FoundationModelsWorkCoordinator = .shared
    ) {
        self.availability = availability
        self.workCoordinator = workCoordinator
    }

    public func draft(from prompt: String, accounts: [Account]) async throws -> CategorizationRuleDraft {
        guard await availability.availability() == .available else {
            throw CashFlowError.intelligenceUnavailable
        }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CashFlowError.intelligence(message: "Describe the rule you want.")
        }

        let accountLines = accounts
            .map { "- \($0.name) (id=\($0.id.rawValue))" }
            .joined(separator: "\n")

        do {
            return try await workCoordinator.runExclusive {
                let model = FoundationModelsWorkCoordinator.contentTransformationModel()
                let session = LanguageModelSession(
                    model: model,
                    instructions: """
                    You draft personal finance categorization rules for Cash Flow.
                    Output must match the app's rule editor: an action (categorize or rename), \
                    optional category or rename title, and AND conditions.
                    Prefer titleContains for merchant names. Use account only when the user names an account.
                    Use amountMin/amountMax only when the user specifies amounts.
                    Do not invent conditions the user did not imply.
                    """
                )
                let response = try await session.respond(
                    to: """
                    Draft a categorization rule from this request:
                    \(trimmed)

                    Available accounts:
                    \(accountLines.isEmpty ? "(none)" : accountLines)
                    """,
                    generating: GenerableRuleDraft.self
                )
                return try Self.map(response.content, accounts: accounts)
            }
        } catch let error as CashFlowError {
            throw error
        } catch {
            throw CashFlowError.intelligence(
                message: FoundationModelsWorkCoordinator.userFacingMessage(for: error)
            )
        }
    }

    private static func map(
        _ generated: GenerableRuleDraft,
        accounts: [Account]
    ) throws -> CategorizationRuleDraft {
        let action: CategorizationRuleDraft.Action
        switch generated.action.lowercased() {
        case "rename":
            action = .rename
        default:
            action = .categorize
        }

        let categoryID = SystemCategory.allCases
            .first { $0.name == generated.categoryName }?
            .id ?? SystemCategory.other.id

        let rename = generated.renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let conditions = generated.conditions.compactMap { condition -> CategorizationCondition? in
            mapCondition(condition, accounts: accounts)
        }
        guard !conditions.isEmpty else {
            throw CashFlowError.intelligence(message: "Couldn't find any valid rule conditions.")
        }
        if action == .rename, rename.isEmpty {
            throw CashFlowError.intelligence(message: "Rename rules need a new merchant title.")
        }

        return CategorizationRuleDraft(
            action: action,
            categoryID: categoryID,
            renameTitle: action == .rename ? rename : nil,
            conditions: conditions,
            explanation: generated.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func mapCondition(
        _ condition: GenerableRuleCondition,
        accounts: [Account]
    ) -> CategorizationCondition? {
        let text = condition.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountText = condition.amountValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        switch condition.kind {
        case "titleContains":
            guard !text.isEmpty else { return nil }
            return .titleContains(text)
        case "titleEquals":
            guard !text.isEmpty else { return nil }
            return .titleEquals(text)
        case "descriptionContains":
            guard !text.isEmpty else { return nil }
            return .descriptionContains(text)
        case "descriptionEquals":
            guard !text.isEmpty else { return nil }
            return .descriptionEquals(text)
        case "locationContains":
            guard !text.isEmpty else { return nil }
            return .locationContains(text)
        case "categoryIs":
            guard let category = SystemCategory.allCases.first(where: {
                $0.name.localizedCaseInsensitiveCompare(text) == .orderedSame
                    || $0.rawValue.localizedCaseInsensitiveCompare(text) == .orderedSame
            }) else { return nil }
            return .categoryIs(category.id)
        case "account":
            guard !text.isEmpty else { return nil }
            if let match = accounts.first(where: {
                $0.name.localizedCaseInsensitiveCompare(text) == .orderedSame
                    || $0.id.rawValue == text
            }) {
                return .accountID(match.id)
            }
            return nil
        case "amountMin":
            guard let amount = Decimal(string: amountText) else { return nil }
            return .amountMin(amount)
        case "amountMax":
            guard let amount = Decimal(string: amountText) else { return nil }
            return .amountMax(amount)
        default:
            return nil
        }
    }
}
#endif

public struct UnavailableCategorizationRuleDrafting: CategorizationRuleDrafting {
    public init() {}

    public func draft(from prompt: String, accounts: [Account]) async throws -> CategorizationRuleDraft {
        throw CashFlowError.intelligenceUnavailable
    }
}

public enum CategorizationRuleDraftingFactory {
    public static func make(
        availability: any OnDeviceModelAvailabilityChecking
    ) -> any CategorizationRuleDrafting {
        if #available(iOS 26, macOS 26, *) {
            #if canImport(FoundationModels)
            return FoundationModelsRuleDrafting(availability: availability)
            #else
            return UnavailableCategorizationRuleDrafting()
            #endif
        }
        return UnavailableCategorizationRuleDrafting()
    }
}
