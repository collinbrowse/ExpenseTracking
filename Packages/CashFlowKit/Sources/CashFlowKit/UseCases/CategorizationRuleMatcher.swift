import Foundation

public enum CategorizationRuleMatcher: Sendable {
    /// Evaluates a rule against a transaction’s current (start-of-pass) state.
    public static func matches(_ rule: CategorizationRule, transaction: Transaction) -> Bool {
        guard rule.isEnabled, !rule.conditions.isEmpty else { return false }
        // After a rename rule runs, the visible title/location become the rename values.
        // Treat text conditions as satisfied so re-apply / relaunch still keep the rule.
        let alreadyRenamed = rule.renameTitle.map {
            TransactionDescriptionMatcher.equals(transaction.displayTitle, other: $0)
        } ?? false
        let alreadyRelocated = rule.renameLocation.map { rename in
            guard let location = transaction.displayLocation else { return false }
            return TransactionDescriptionMatcher.equals(location, other: rename)
        } ?? false

        return rule.conditions.allSatisfy { condition in
            if alreadyRenamed, isStickyTitleCondition(condition) {
                return true
            }
            if alreadyRelocated, isStickyLocationCondition(condition) {
                return true
            }
            if (alreadyRenamed || alreadyRelocated), isStickyDescriptionCondition(condition) {
                return true
            }
            return matches(condition, transaction: transaction)
        }
    }

    public static func matches(
        _ condition: CategorizationCondition,
        transaction: Transaction
    ) -> Bool {
        let description = transaction.description
        let amount = transaction.amount
        let accountID = transaction.accountID
        switch condition {
        case .titleContains(let needle):
            // Union of raw bank text and titled enrichment so rules stay stable across enrichment.
            if TransactionDescriptionMatcher.contains(description, needle: needle) {
                return true
            }
            if let enriched = transaction.enrichedTitle,
               TransactionDescriptionMatcher.contains(enriched, needle: needle)
            {
                return true
            }
            if let location = transaction.enrichedLocation,
               TransactionDescriptionMatcher.contains(location, needle: needle)
            {
                return true
            }
            return false
        case .titleEquals(let value):
            if TransactionDescriptionMatcher.equals(transaction.displayTitle, other: value) {
                return true
            }
            return TransactionDescriptionMatcher.equals(description, other: value)
        case .descriptionContains(let needle):
            return TransactionDescriptionMatcher.contains(description, needle: needle)
        case .descriptionEquals(let value):
            return TransactionDescriptionMatcher.equals(description, other: value)
        case .locationContains(let needle):
            if let location = transaction.displayLocation {
                return TransactionDescriptionMatcher.contains(location, needle: needle)
            }
            // Pre-enrichment: fall back to the raw bank string.
            return TransactionDescriptionMatcher.contains(description, needle: needle)
        case .categoryIs(let expected):
            return transaction.categoryID == expected
        case .hasTag(let tagID):
            return transaction.tagIDs.contains(tagID)
        case .accountID(let expected):
            return accountID == expected
        case .amountMin(let min):
            return amount >= min
        case .amountMax(let max):
            return amount <= max
        }
    }

    /// All enabled matching rules in priority order (first is the one Resolve applies for category).
    public static func matchingRules(
        _ rules: [CategorizationRule],
        transaction: Transaction
    ) -> [CategorizationRule] {
        rules.filter(\.isEnabled).sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.id < $1.id
        }
        .filter { matches($0, transaction: transaction) }
    }

    /// First enabled rule by ascending priority that matches, if any.
    public static func firstMatchingRule(
        _ rules: [CategorizationRule],
        transaction: Transaction
    ) -> CategorizationRule? {
        matchingRules(rules, transaction: transaction).first
    }

    /// Convenience for tests and call sites that only have primitives (no enrichment/tags).
    public static func matches(
        _ rule: CategorizationRule,
        description: String,
        amount: Decimal,
        accountID: AccountID,
        categoryID: CategoryID = SystemCategory.other.id,
        tagIDs: [TagID] = [],
        enrichedTitle: String? = nil,
        enrichedLocation: String? = nil,
        titleSource: TitleSource? = nil
    ) -> Bool {
        matches(
            rule,
            transaction: Transaction(
                id: TransactionID("match"),
                accountID: accountID,
                externalID: "match",
                amount: amount,
                postedDate: .distantPast,
                description: description,
                categoryID: categoryID,
                tagIDs: tagIDs,
                enrichedTitle: enrichedTitle,
                enrichedLocation: enrichedLocation,
                titleSource: titleSource
            )
        )
    }

    /// Convenience wrapper matching the historical primitive API.
    public static func matchingRules(
        _ rules: [CategorizationRule],
        description: String,
        amount: Decimal,
        accountID: AccountID,
        categoryID: CategoryID = SystemCategory.other.id,
        tagIDs: [TagID] = []
    ) -> [CategorizationRule] {
        matchingRules(
            rules,
            transaction: Transaction(
                id: TransactionID("match"),
                accountID: accountID,
                externalID: "match",
                amount: amount,
                postedDate: .distantPast,
                description: description,
                categoryID: categoryID,
                tagIDs: tagIDs
            )
        )
    }

    public static func firstMatchingRule(
        _ rules: [CategorizationRule],
        description: String,
        amount: Decimal,
        accountID: AccountID
    ) -> CategorizationRule? {
        matchingRules(rules, description: description, amount: amount, accountID: accountID).first
    }

    private static func isStickyTitleCondition(_ condition: CategorizationCondition) -> Bool {
        switch condition {
        case .titleContains, .titleEquals:
            return true
        default:
            return false
        }
    }

    private static func isStickyLocationCondition(_ condition: CategorizationCondition) -> Bool {
        switch condition {
        case .locationContains:
            return true
        default:
            return false
        }
    }

    private static func isStickyDescriptionCondition(_ condition: CategorizationCondition) -> Bool {
        switch condition {
        case .descriptionContains, .descriptionEquals:
            return true
        default:
            return false
        }
    }
}
