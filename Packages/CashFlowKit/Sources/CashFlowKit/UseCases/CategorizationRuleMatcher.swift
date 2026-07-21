import Foundation

public enum CategorizationRuleMatcher: Sendable {
    public static func matches(
        _ rule: CategorizationRule,
        description: String,
        amount: Decimal,
        accountID: AccountID
    ) -> Bool {
        guard rule.isEnabled, !rule.conditions.isEmpty else { return false }
        let parsed = ParseTransactionDescriptionUseCase.execute(description)
        // After a rename rule runs, local title becomes `renameTitle`. Treat text
        // conditions as satisfied so re-apply / relaunch still keep the rule.
        let alreadyRenamed = rule.renameTitle.map {
            TransactionDescriptionMatcher.equals(parsed.title, other: $0)
        } ?? false

        return rule.conditions.allSatisfy { condition in
            if alreadyRenamed, isTextCondition(condition) {
                return true
            }
            return matches(
                condition,
                description: description,
                amount: amount,
                accountID: accountID
            )
        }
    }

    public static func matches(
        _ condition: CategorizationCondition,
        description: String,
        amount: Decimal,
        accountID: AccountID
    ) -> Bool {
        let parsed = ParseTransactionDescriptionUseCase.execute(description)
        switch condition {
        case .titleContains(let needle):
            // Match words across the merchant title and any parsed location suffix.
            // Banks often pad with double spaces mid-string; those words still belong
            // to what users think of as the title.
            let titleHaystack = ParsedTransactionDescription.recombine(
                title: parsed.title,
                location: parsed.location
            )
            return TransactionDescriptionMatcher.contains(titleHaystack, needle: needle)
        case .titleEquals(let value):
            return TransactionDescriptionMatcher.equals(parsed.title, other: value)
        case .descriptionContains(let needle):
            return TransactionDescriptionMatcher.contains(description, needle: needle)
        case .descriptionEquals(let value):
            return TransactionDescriptionMatcher.equals(description, other: value)
        case .accountID(let expected):
            return accountID == expected
        case .amountMin(let min):
            return amount >= min
        case .amountMax(let max):
            return amount <= max
        }
    }

    /// All enabled matching rules in priority order (first is the one Resolve applies).
    public static func matchingRules(
        _ rules: [CategorizationRule],
        description: String,
        amount: Decimal,
        accountID: AccountID
    ) -> [CategorizationRule] {
        rules.filter(\.isEnabled).sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.id < $1.id
        }
        .filter {
            matches($0, description: description, amount: amount, accountID: accountID)
        }
    }

    /// First enabled rule by ascending priority that matches, if any.
    public static func firstMatchingRule(
        _ rules: [CategorizationRule],
        description: String,
        amount: Decimal,
        accountID: AccountID
    ) -> CategorizationRule? {
        matchingRules(rules, description: description, amount: amount, accountID: accountID).first
    }

    private static func isTextCondition(_ condition: CategorizationCondition) -> Bool {
        switch condition {
        case .titleContains, .titleEquals, .descriptionContains, .descriptionEquals:
            return true
        case .accountID, .amountMin, .amountMax:
            return false
        }
    }
}
