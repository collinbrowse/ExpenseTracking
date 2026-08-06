import Foundation
import CashFlowKit

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
@Generable
struct GenerableIntentCondition {
    @Guide(
        description: "Condition kind",
        .anyOf([
            "titleContains",
            "titleEquals",
            "descriptionContains",
            "descriptionEquals",
            "locationContains",
            "categoryIs",
            "hasTag",
            "account",
            "amountMin",
            "amountMax",
        ])
    )
    var kind: String

    @Guide(description: "Text for title/description/location, account name, category name, or tag name; empty for amounts")
    var textValue: String

    @Guide(description: "Decimal amount for amountMin/amountMax without currency symbols; empty otherwise")
    var amountValue: String
}

@available(iOS 26, macOS 26, *)
@Generable
struct GenerableAssistantIntent {
    @Guide(description: "Short explanation of what will happen for the user")
    var explanation: String

    @Guide(description: "True when the request should set a system category")
    var appliesCategory: Bool

    @Guide(
        description: "System category display name when appliesCategory is true",
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

    @Guide(description: "New merchant title for a one-shot rename; empty when not renaming")
    var renameTitle: String

    @Guide(description: "New location for a one-shot location change; empty when not setting one")
    var renameLocation: String

    @Guide(
        description: "Tag names only when the user explicitly asked to tag; otherwise empty",
        .maximumCount(6)
    )
    var tagNames: [String]

    @Guide(description: "True when the user wants this to keep applying to future transactions")
    var prefersSavingRule: Bool

    @Guide(description: "AND conditions that must all match", .maximumCount(6))
    var conditions: [GenerableIntentCondition]
}

@available(iOS 26, macOS 26, *)
public struct FoundationModelsIntentInterpreting: TransactionIntentInterpreting {
    private let availability: any OnDeviceModelAvailabilityChecking
    private let workCoordinator: FoundationModelsWorkCoordinator

    public init(
        availability: any OnDeviceModelAvailabilityChecking,
        workCoordinator: FoundationModelsWorkCoordinator
    ) {
        self.availability = availability
        self.workCoordinator = workCoordinator
    }

    public func interpret(
        prompt: String,
        accounts: [Account],
        tags: [Tag]
    ) -> AsyncThrowingStream<AssistantIntentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard await availability.availability() == .available else {
                        throw CashFlowError.intelligenceUnavailable
                    }
                    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        throw CashFlowError.intelligence(
                            message: "Ask to tag or categorize transactions."
                        )
                    }

                    let accountLines = accounts.map { "- \($0.name)" }.joined(separator: "\n")
                    let tagLines = tags.map { "- \($0.name)" }.joined(separator: "\n")
                    let categoryLines = SystemCategory.allCases.map { "- \($0.name)" }
                        .joined(separator: "\n")

                    let finalIntent: AssistantIntent = try await workCoordinator.runExclusive {
                        let model = FoundationModelsWorkCoordinator.contentTransformationModel()
                        let session = LanguageModelSession(
                            model: model,
                            instructions: """
                            You interpret personal finance requests into lasting rule conditions and actions.
                            Output structured conditions only — never list individual transactions.
                            Prefer locationContains for place names (cities, countries, regions).
                            Prefer titleContains for merchant names.
                            Use hasTag / categoryIs only when the user clearly refers to an existing tag or category.
                            Use account / amount bounds only when the user specifies them.
                            Fill tagNames ONLY when the user explicitly asks to tag or add a tag.
                            Categorize-only requests must set appliesCategory and leave tagNames empty.
                            Never invent a tag that duplicates the chosen category name or any system category name.
                            Set prefersSavingRule true unless the user clearly wants a one-time change.
                            Rename titles are one-shot (not lasting rules).
                            Do not invent conditions the user did not imply.
                            """
                        )
                        let promptText = """
                        Interpret this request:
                        \(trimmed)

                        Available accounts:
                        \(accountLines.isEmpty ? "(none)" : accountLines)

                        Existing tags:
                        \(tagLines.isEmpty ? "(none)" : tagLines)

                        System categories:
                        \(categoryLines)
                        """
                        let stream = session.streamResponse(
                            to: promptText,
                            generating: GenerableAssistantIntent.self
                        )
                        var lastPartial: GenerableAssistantIntent.PartiallyGenerated?
                        for try await snapshot in stream {
                            lastPartial = snapshot.content
                            if let draft = Self.draftEvent(
                                from: snapshot.content,
                                accounts: accounts,
                                tags: tags
                            ) {
                                continuation.yield(draft)
                            }
                        }
                        guard let lastPartial else {
                            throw CashFlowError.intelligence(
                                message: "Couldn't interpret that request."
                            )
                        }
                        let completed = try Self.complete(lastPartial)
                        return try Self.map(completed, accounts: accounts, tags: tags)
                    }

                    continuation.yield(.intent(finalIntent))
                    continuation.finish()
                } catch let error as CashFlowError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(
                        throwing: CashFlowError.intelligence(
                            message: FoundationModelsWorkCoordinator.userFacingMessage(for: error)
                        )
                    )
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func draftEvent(
        from generated: GenerableAssistantIntent.PartiallyGenerated,
        accounts: [Account],
        tags: [Tag]
    ) -> AssistantIntentStreamEvent? {
        let explanation = generated.explanation?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let partialConditions = (generated.conditions ?? []).compactMap { partial -> CategorizationCondition? in
            guard let kind = partial.kind else { return nil }
            let mapped = GenerableIntentCondition(
                kind: kind,
                textValue: partial.textValue ?? "",
                amountValue: partial.amountValue ?? ""
            )
            return mapCondition(mapped, accounts: accounts, tags: tags)
        }
        guard !explanation.isEmpty || !partialConditions.isEmpty else { return nil }
        let summary = partialConditions.isEmpty
            ? ""
            : CategorizationConditionFormatting.summary(for: partialConditions)
        return .draft(explanation: explanation, conditionSummary: summary)
    }

    private static func complete(
        _ partial: GenerableAssistantIntent.PartiallyGenerated
    ) throws -> GenerableAssistantIntent {
        guard
            let explanation = partial.explanation,
            let appliesCategory = partial.appliesCategory,
            let categoryName = partial.categoryName,
            let renameTitle = partial.renameTitle,
            let renameLocation = partial.renameLocation,
            let tagNames = partial.tagNames,
            let prefersSavingRule = partial.prefersSavingRule,
            let conditions = partial.conditions
        else {
            throw CashFlowError.intelligence(message: "Couldn't interpret that request.")
        }
        let completedConditions: [GenerableIntentCondition] = try conditions.map { condition in
            guard let kind = condition.kind else {
                throw CashFlowError.intelligence(message: "Couldn't interpret that request.")
            }
            return GenerableIntentCondition(
                kind: kind,
                textValue: condition.textValue ?? "",
                amountValue: condition.amountValue ?? ""
            )
        }
        return GenerableAssistantIntent(
            explanation: explanation,
            appliesCategory: appliesCategory,
            categoryName: categoryName,
            renameTitle: renameTitle,
            renameLocation: renameLocation,
            tagNames: tagNames,
            prefersSavingRule: prefersSavingRule,
            conditions: completedConditions
        )
    }

    private static func map(
        _ generated: GenerableAssistantIntent,
        accounts: [Account],
        tags: [Tag]
    ) throws -> AssistantIntent {
        let conditions = generated.conditions.compactMap {
            mapCondition($0, accounts: accounts, tags: tags)
        }
        guard !conditions.isEmpty else {
            throw CashFlowError.intelligence(
                message: "Couldn't find any matching conditions in that request."
            )
        }

        let categoryID = SystemCategory.allCases
            .first { $0.name == generated.categoryName }?
            .id ?? SystemCategory.other.id
        let rename = generated.renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let renameLocation = generated.renameLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagNames = SanitizeAssistantIntentTagsUseCase.execute(
            appliesCategory: generated.appliesCategory,
            categoryID: categoryID,
            tagNames: generated.tagNames
        )

        let intent = AssistantIntent(
            explanation: generated.explanation.trimmingCharacters(in: .whitespacesAndNewlines),
            conditions: conditions,
            appliesCategory: generated.appliesCategory,
            categoryID: categoryID,
            renameTitle: rename.isEmpty ? nil : rename,
            renameLocation: renameLocation.isEmpty ? nil : renameLocation,
            tagNames: tagNames,
            prefersSavingRule: generated.prefersSavingRule
        )
        guard intent.hasAction else {
            throw CashFlowError.intelligence(
                message: "Say what to change — a category, tags, or a rename."
            )
        }
        return intent
    }

    private static func mapCondition(
        _ condition: GenerableIntentCondition,
        accounts: [Account],
        tags: [Tag]
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
        case "hasTag":
            guard let tag = tags.first(where: {
                $0.name.localizedCaseInsensitiveCompare(text) == .orderedSame
            }) else { return nil }
            return .hasTag(tag.id)
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

public struct UnavailableIntentInterpreting: TransactionIntentInterpreting {
    public init() {}

    public func interpret(
        prompt: String,
        accounts: [Account],
        tags: [Tag]
    ) -> AsyncThrowingStream<AssistantIntentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CashFlowError.intelligenceUnavailable)
        }
    }
}

public enum TransactionIntentInterpretingFactory {
    public static func make(
        availability: any OnDeviceModelAvailabilityChecking,
        workCoordinator: FoundationModelsWorkCoordinator
    ) -> any TransactionIntentInterpreting {
        if #available(iOS 26, macOS 26, *) {
            #if canImport(FoundationModels)
            return FoundationModelsIntentInterpreting(
                availability: availability,
                workCoordinator: workCoordinator
            )
            #else
            return UnavailableIntentInterpreting()
            #endif
        }
        return UnavailableIntentInterpreting()
    }
}
