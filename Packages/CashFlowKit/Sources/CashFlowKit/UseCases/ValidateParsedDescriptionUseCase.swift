import Foundation

/// Validates LLM (or memo) merchant/location parses against the raw bank description.
/// Rejects schema leaks, hallucinations, and invented geography for unattended enrichment.
/// When the model leaves location words in the title, strips that trailing location suffix.
public enum ValidateParsedDescriptionUseCase: Sendable {
    public static let maxTitleLength = 120
    public static let maxLocationLength = 80

    /// Returns a cleaned parse when valid; `nil` when the result must not be persisted.
    public static func execute(
        title: String,
        location: String?,
        rawDescription: String
    ) -> ParsedTransactionDescription? {
        let raw = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !trimmedTitle.isEmpty else { return nil }
        guard trimmedTitle.count <= maxTitleLength else { return nil }
        guard !containsControlCharacters(trimmedTitle) else { return nil }

        let rawTokens = tokenSet(raw)
        guard !rawTokens.isEmpty else { return nil }

        let cleanedLocation: String?
        if let location {
            let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLocation.isEmpty {
                cleanedLocation = nil
            } else {
                guard trimmedLocation.count <= maxLocationLength else { return nil }
                guard !containsControlCharacters(trimmedLocation) else { return nil }
                let locationTokens = tokenSet(trimmedLocation)
                guard !locationTokens.isEmpty, locationTokens.isSubset(of: rawTokens) else {
                    return nil
                }
                cleanedLocation = trimmedLocation
            }
        } else {
            cleanedLocation = nil
        }

        if let cleanedLocation {
            // Title that is only the location (or equals it) is not a merchant name.
            if TransactionDescriptionMatcher.equals(trimmedTitle, other: cleanedLocation) {
                return nil
            }
            if let stripped = strippingTrailingLocation(from: trimmedTitle, location: cleanedLocation) {
                trimmedTitle = stripped
            }
        }
        guard !trimmedTitle.isEmpty else { return nil }
        guard trimmedTitle.count <= maxTitleLength else { return nil }

        let titleTokens = tokenSet(trimmedTitle)
        guard !titleTokens.isEmpty else { return nil }
        // Near-subset: every title token must appear in the raw description.
        guard titleTokens.isSubset(of: rawTokens) else { return nil }
        // After strip, title must still differ from location.
        if let cleanedLocation,
           TransactionDescriptionMatcher.equals(trimmedTitle, other: cleanedLocation)
        {
            return nil
        }

        return ParsedTransactionDescription(
            title: trimmedTitle,
            location: cleanedLocation,
            raw: raw
        )
    }

    /// When `location` is a trailing token suffix of `title`, returns the title prefix with
    /// that suffix removed (preserves original word casing). Returns `nil` when there is
    /// nothing to strip.
    static func strippingTrailingLocation(from title: String, location: String) -> String? {
        let locationTokens = tokenList(location)
        guard !locationTokens.isEmpty else { return nil }

        let titleTokens = tokenList(title)
        guard titleTokens.count > locationTokens.count else { return nil }
        let suffix = Array(titleTokens.suffix(locationTokens.count))
        guard suffix == locationTokens else { return nil }

        let keepCount = titleTokens.count - locationTokens.count
        let words = title.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept: [String] = []
        var tokensKept = 0
        for word in words {
            let wordTokens = tokenList(word)
            guard !wordTokens.isEmpty else { continue }
            if tokensKept >= keepCount { break }
            guard tokensKept + wordTokens.count <= keepCount else { break }
            kept.append(word)
            tokensKept += wordTokens.count
        }
        let stripped = kept.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, stripped != title.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return stripped
    }

    private static func containsControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func tokenSet(_ value: String) -> Set<String> {
        Set(tokenList(value))
    }

    private static func tokenList(_ value: String) -> [String] {
        TransactionDescriptionMatcher.tokens(in: TransactionDescriptionMatcher.normalize(value))
    }
}
