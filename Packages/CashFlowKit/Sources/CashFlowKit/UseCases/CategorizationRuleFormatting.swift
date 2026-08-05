import Foundation

/// User-facing one-line description of a rule: when it matches and what it does.
public enum CategorizationRuleFormatting: Sendable {
    public static func summary(
        for rule: CategorizationRule,
        accountName: (AccountID) -> String = { _ in "Account" },
        categoryName: (CategoryID) -> String = { SystemCategory.category(for: $0).name },
        tagName: (TagID) -> String = { _ in "Tag" }
    ) -> String {
        let when = CategorizationConditionFormatting.summary(
            for: rule.conditions,
            accountName: accountName,
            categoryName: categoryName,
            tagName: tagName
        )
        let actions = actionPhrases(
            for: rule,
            categoryName: categoryName,
            tagName: tagName
        )
        guard !actions.isEmpty else { return when }
        let then = actions.joined(separator: "\n")
        if when.isEmpty { return then }
        return "\(when)\n\(then)"
    }

    private static func actionPhrases(
        for rule: CategorizationRule,
        categoryName: (CategoryID) -> String,
        tagName: (TagID) -> String
    ) -> [String] {
        var phrases: [String] = []
        if rule.appliesCategory {
            phrases.append("Category set as \(categoryName(rule.categoryID))")
        }
        if let renameTitle = rule.renameTitle {
            phrases.append("Rename title to “\(renameTitle)”")
        }
        if !rule.tagIDs.isEmpty {
            let names = rule.tagIDs.map(tagName)
            if names.count == 1 {
                phrases.append("Add tag \(names[0])")
            } else {
                phrases.append("Add tags \(names.joined(separator: ", "))")
            }
        }
        return phrases
    }
}
