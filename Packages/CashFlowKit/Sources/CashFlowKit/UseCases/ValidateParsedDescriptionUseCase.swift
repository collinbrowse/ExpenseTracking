import Foundation

/// Validates LLM (or memo) merchant/location parses against the raw bank description.
/// Rejects schema leaks, hallucinations, and invented geography for unattended enrichment.
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
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !trimmedTitle.isEmpty else { return nil }
        guard trimmedTitle.count <= maxTitleLength else { return nil }
        guard !containsControlCharacters(trimmedTitle) else { return nil }

        let rawTokens = tokenSet(raw)
        guard !rawTokens.isEmpty else { return nil }
        let titleTokens = tokenSet(trimmedTitle)
        guard !titleTokens.isEmpty else { return nil }
        // Near-subset: every title token must appear in the raw description.
        guard titleTokens.isSubset(of: rawTokens) else { return nil }

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

        return ParsedTransactionDescription(
            title: trimmedTitle,
            location: cleanedLocation,
            raw: raw
        )
    }

    private static func containsControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func tokenSet(_ value: String) -> Set<String> {
        Set(TransactionDescriptionMatcher.tokens(in: TransactionDescriptionMatcher.normalize(value)))
    }
}
