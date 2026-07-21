import Foundation

/// Shared normalize / token / phrase matching for built-in suggestions and user rules.
public enum TransactionDescriptionMatcher: Sendable {
    public static func normalize(_ description: String) -> String {
        description
            .lowercased()
            .replacingOccurrences(of: "*", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "#", with: " ")
    }

    public static func tokens(in haystack: String) -> [String] {
        haystack
            .split { !($0.isLetter || $0.isNumber || $0 == "&") }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    public static func matchesAnyWord(_ haystack: String, _ words: [String]) -> Bool {
        let tokenSet = Set(tokens(in: haystack))
        for word in words where !word.contains(" ") {
            if tokenSet.contains(word) { return true }
            if tokenSet.contains(where: {
                $0 == word || ($0.hasPrefix(word) && $0.count <= word.count + 2)
            }) {
                return true
            }
        }
        return false
    }

    public static func matchesAnyPhrase(_ haystack: String, _ phrases: [String]) -> Bool {
        phrases.contains { haystack.contains($0) }
    }

    /// True when every word in `needle` appears as a whole word in `haystack`
    /// (order and adjacency do not matter). "Income Payment" matches
    /// "Income Benefits Payment, March 2026"; "fee" does not match "coffee".
    public static func contains(_ haystack: String, needle: String) -> Bool {
        let needleTokens = tokens(in: normalize(needle))
        guard !needleTokens.isEmpty else { return false }
        let haystackTokens = Set(tokens(in: normalize(haystack)))
        return needleTokens.allSatisfy(haystackTokens.contains)
    }

    public static func equals(_ haystack: String, other: String) -> Bool {
        let left = normalize(haystack).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = normalize(other).trimmingCharacters(in: .whitespacesAndNewlines)
        return left == right
    }
}
