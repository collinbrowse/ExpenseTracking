import Foundation

public struct ResolvedCategory: Equatable, Sendable {
    public let categoryID: CategoryID
    public let matchedUserRule: Bool
    /// Merchant title to apply when a matching rename rule exists.
    public let renameTitle: String?

    public init(
        categoryID: CategoryID,
        matchedUserRule: Bool,
        renameTitle: String? = nil
    ) {
        self.categoryID = categoryID
        self.matchedUserRule = matchedUserRule
        self.renameTitle = renameTitle
    }
}

/// Resolves category + rename from user rules independently, then falls back to built-in suggestion.
///
/// `categoryLocked` blocks category changes only — rename rules still apply.
public enum ResolveTransactionCategoryUseCase: Sendable {
    public static func execute(
        description: String,
        amount: Decimal,
        accountID: AccountID,
        rules: [CategorizationRule],
        categoryLocked: Bool,
        currentCategoryID: CategoryID,
        fallbackCategoryID: CategoryID? = nil
    ) -> ResolvedCategory {
        let matching = CategorizationRuleMatcher.matchingRules(
            rules,
            description: description,
            amount: amount,
            accountID: accountID
        )
        let categoryRule = categoryLocked ? nil : matching.first(where: \.appliesCategory)
        let renameRule = matching.first(where: { $0.renameTitle != nil })

        if categoryRule != nil || renameRule != nil {
            let categoryID = categoryRule?.categoryID ?? currentCategoryID
            return ResolvedCategory(
                categoryID: categoryID,
                matchedUserRule: true,
                renameTitle: renameRule?.renameTitle
            )
        }

        if categoryLocked {
            return ResolvedCategory(
                categoryID: currentCategoryID,
                matchedUserRule: false,
                renameTitle: nil
            )
        }

        if let fallbackCategoryID {
            return ResolvedCategory(
                categoryID: fallbackCategoryID,
                matchedUserRule: false,
                renameTitle: nil
            )
        }

        let parsedTitle = ParseTransactionDescriptionUseCase.execute(description).title
        let suggested = SuggestTransactionCategoryUseCase.execute(
            description: parsedTitle,
            amount: amount
        )
        return ResolvedCategory(
            categoryID: suggested,
            matchedUserRule: false,
            renameTitle: nil
        )
    }

    /// Replaces the merchant title while keeping any parsed location suffix.
    public static func applyingRename(to description: String, renameTitle: String) -> String {
        let parsed = ParseTransactionDescriptionUseCase.execute(description)
        return ParsedTransactionDescription.recombine(
            title: renameTitle,
            location: parsed.location
        )
    }
}
