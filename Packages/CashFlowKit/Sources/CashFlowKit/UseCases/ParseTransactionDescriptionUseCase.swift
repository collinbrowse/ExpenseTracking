import Foundation

/// Merchant title + optional location parsed from a bank/SimpleFIN description.
/// Banks often pad with spaces or append `"CITY ST"` / `"CITY, ST"` at the end.
public struct ParsedTransactionDescription: Equatable, Sendable {
    public let title: String
    public let location: String?
    public let raw: String

    public init(title: String, location: String?, raw: String) {
        self.title = title
        self.location = location
        self.raw = raw
    }

    /// Rebuilds a storable description so location survives a title-only edit.
    public static func recombine(title: String, location: String?) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let location,
              !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return trimmedTitle
        }
        let trimmedLocation = collapseWhitespace(location)
        return "\(trimmedTitle)  \(trimmedLocation)"
    }

    fileprivate static func collapseWhitespace(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

public enum ParseTransactionDescriptionUseCase: Sendable {
    public static func execute(_ raw: String) -> ParsedTransactionDescription {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedTransactionDescription(title: "", location: nil, raw: "")
        }

        if let padded = splitOnWidePadding(trimmed) {
            return padded
        }
        if let trailing = extractTrailingCityState(trimmed), !trailing.prefix.isEmpty {
            return ParsedTransactionDescription(
                title: trailing.prefix,
                location: trailing.location,
                raw: trimmed
            )
        }

        let collapsed = ParsedTransactionDescription.collapseWhitespace(trimmed)
        return ParsedTransactionDescription(title: collapsed, location: nil, raw: trimmed)
    }

    // MARK: - Wide padding (2+ spaces)

    private static func splitOnWidePadding(_ trimmed: String) -> ParsedTransactionDescription? {
        guard let match = trimmed.range(of: #"\s{2,}"#, options: .regularExpression) else {
            return nil
        }

        let title = String(trimmed[..<match.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = ParsedTransactionDescription.collapseWhitespace(
            String(trimmed[match.upperBound...])
        )
        guard !title.isEmpty, !tail.isEmpty else { return nil }

        if let cityState = extractTrailingCityState(tail, preferWholeTailAsLocation: true) {
            let merchant = cityState.prefix.isEmpty
                ? title
                : ParsedTransactionDescription.collapseWhitespace("\(title) \(cityState.prefix)")
            return ParsedTransactionDescription(
                title: merchant,
                location: cityState.location,
                raw: trimmed
            )
        }

        guard looksLikeLooseLocation(tail) else { return nil }
        return ParsedTransactionDescription(title: title, location: tail, raw: trimmed)
    }

    // MARK: - Trailing "City ST" / "City, ST"

    private struct CityStateSplit {
        let prefix: String
        let location: String
        let cityWordCount: Int
        let cityLeadToken: String
    }

    private static func extractTrailingCityState(
        _ text: String,
        preferWholeTailAsLocation: Bool = false
    ) -> CityStateSplit? {
        let collapsed = ParsedTransactionDescription.collapseWhitespace(text)
        var tokens = collapsed.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return nil }

        if tokens[tokens.count - 2].hasSuffix(",") {
            tokens[tokens.count - 2] = String(tokens[tokens.count - 2].dropLast())
        }

        let stateToken = tokens[tokens.count - 1]
            .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
            .uppercased()
        guard usStateCodes.contains(stateToken) else { return nil }

        var candidates: [CityStateSplit] = []
        let maxCityWords = min(3, tokens.count - 1)
        for cityWordCount in 1...maxCityWords {
            let cityStart = tokens.count - 1 - cityWordCount
            let cityTokens = Array(tokens[cityStart..<(tokens.count - 1)])
            guard isPlausibleCity(cityTokens) else { continue }

            let prefix = Array(tokens[..<cityStart]).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayLocation = (cityTokens + [stateToken]).joined(separator: " ")
                .replacingOccurrences(of: ",", with: "")
            let lead = cityTokens[0]
                .trimmingCharacters(in: CharacterSet(charactersIn: ",."))
                .uppercased()

            candidates.append(
                CityStateSplit(
                    prefix: prefix,
                    location: displayLocation,
                    cityWordCount: cityWordCount,
                    cityLeadToken: lead
                )
            )
        }
        guard !candidates.isEmpty else { return nil }

        if preferWholeTailAsLocation,
           let whole = candidates
            .filter({ $0.prefix.isEmpty })
            .max(by: { $0.cityWordCount < $1.cityWordCount })
        {
            return whole
        }

        if let best = candidates
            .filter({ !$0.prefix.isEmpty })
            .max(by: { locationRank($0) < locationRank($1) })
        {
            return best
        }

        return candidates
            .filter { $0.prefix.isEmpty }
            .max(by: { $0.cityWordCount < $1.cityWordCount })
    }

    /// Higher is better. Multi-word cities (Fort Collins, San Diego) beat a 1-word split.
    private static func locationRank(_ split: CityStateSplit) -> Int {
        if split.cityWordCount >= 2, multiWordCityStarters.contains(split.cityLeadToken) {
            return 100 + split.cityWordCount
        }
        if split.cityWordCount == 3, multiWordCityStarters.contains(split.cityLeadToken) {
            return 110
        }
        // Default: prefer a single city token (Durango CO over "X Durango CO" as city).
        return 20 - split.cityWordCount
    }

    private static func isPlausibleCity(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        let normalized = tokens.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: ",."))
                .uppercased()
        }
        if normalized.contains(where: { cityTokenBlocklist.contains($0) }) {
            return false
        }
        let letters = normalized.joined().filter(\.isLetter).count
        guard letters >= 3 else { return false }
        if normalized.allSatisfy({ token in
            token.allSatisfy { $0.isNumber || "-#*".contains($0) }
        }) {
            return false
        }
        return true
    }

    private static func looksLikeLooseLocation(_ value: String) -> Bool {
        let letters = value.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 2 else { return false }
        if value.allSatisfy({ $0.isNumber || $0.isWhitespace || "-#*".contains($0) }) {
            return false
        }
        return true
    }

    private static let usStateCodes: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC",
    ]

    private static let multiWordCityStarters: Set<String> = [
        "FORT", "FT", "LAKE", "SAN", "SANTA", "NEW", "NORTH", "SOUTH", "WEST", "EAST",
        "MOUNT", "MT", "ST", "SAINT", "DES", "EL", "LOS", "LAS", "SALT", "COLORADO",
        "BATON", "BOWLING", "CEDAR", "CORAL", "COUNCIL", "GRAND", "GREEN", "LITTLE",
        "OKLAHOMA", "OVERLAND", "PALM", "PARK", "SIOUX", "STATE", "VIRGINIA", "WEST",
    ]

    /// Tokens that often precede "CO" (company) or otherwise aren't place names.
    private static let cityTokenBlocklist: Set<String> = [
        "EXPRESS", "ELECTRIC", "COMPANY", "COMPANIES", "SERVICES", "SERVICE",
        "FINANCIAL", "BANKING", "HOLDINGS", "GROUP", "INTERNATIONAL",
        "NATIONAL", "FEDERAL", "CORPORATION", "CORP", "INSURANCE",
        "CREDIT", "CARD", "PAYMENT", "PAYMENTS", "TRANSFER", "DEPOSIT",
        "INC", "LLC", "LTD", "PLC", "NA",
    ]
}
