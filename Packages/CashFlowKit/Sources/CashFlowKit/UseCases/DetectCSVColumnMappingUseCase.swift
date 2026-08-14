import Foundation

/// Auto-detects column mapping from headers (and optional sample values).
public struct DetectCSVColumnMappingUseCase: Sendable {
    public init() {}

    public func execute(headers: [String], sampleRows: [[String]] = []) -> CSVColumnMapping {
        let normalized = headers.map { Self.normalize($0) }

        if let preset = Self.matchPreset(normalizedHeaders: normalized) {
            return preset
        }

        var assignments: [Int: CSVImportColumn] = [:]
        var used = Set<CSVImportColumn>()

        for (index, header) in normalized.enumerated() {
            guard let column = Self.guessColumn(header: header, used: used) else { continue }
            assignments[index] = column
            if column != .ignore {
                used.insert(column)
            }
        }

        // Debit/credit pair: if we only found "amount" we're fine; if both debit+credit, drop amount.
        if used.contains(.debit) || used.contains(.credit) {
            assignments = assignments.filter { $0.value != .amount }
        }

        _ = sampleRows
        return CSVColumnMapping(assignments: assignments, presetName: nil)
    }

    // MARK: - Presets

    private static func matchPreset(normalizedHeaders: [String]) -> CSVColumnMapping? {
        let set = Set(normalizedHeaders)

        // Our export: posted_date,amount,currency,title,location,category,account,tags,pending,raw_description,external_id
        let ourExport: Set<String> = [
            "posted_date", "amount", "currency", "title", "location", "category",
            "account", "tags", "pending", "raw_description", "external_id",
        ]
        if ourExport.isSubset(of: set) {
            return mapping(
                headers: normalizedHeaders,
                pairs: [
                    "posted_date": .postedDate,
                    "amount": .amount,
                    "currency": .currency,
                    "title": .title,
                    "location": .location,
                    "category": .category,
                    "account": .account,
                    "tags": .tags,
                    "pending": .pending,
                    "raw_description": .description,
                    "external_id": .externalID,
                ],
                preset: "Cash Flow export"
            )
        }

        // Chase-style: Transaction Date, Post Date, Description, Category, Type, Amount, Memo
        if set.contains("transaction date") || set.contains("post date"),
           set.contains("description"),
           set.contains("amount")
        {
            return mapping(
                headers: normalizedHeaders,
                pairs: [
                    "transaction date": .postedDate,
                    "post date": .postedDate,
                    "description": .description,
                    "category": .category,
                    "amount": .amount,
                    "memo": .ignore,
                    "type": .ignore,
                ],
                preset: "Chase"
            )
        }

        // Amex-style: Date, Description, Amount
        if set.contains("date"), set.contains("description"), set.contains("amount"),
           !set.contains("posted_date")
        {
            let hasDebitCredit = set.contains("debit") || set.contains("credit")
            if !hasDebitCredit {
                return mapping(
                    headers: normalizedHeaders,
                    pairs: [
                        "date": .postedDate,
                        "description": .description,
                        "amount": .amount,
                        "extended details": .ignore,
                        "appears on your statement as": .ignore,
                        "reference": .externalID,
                        "category": .category,
                    ],
                    preset: "Amex"
                )
            }
        }

        // Capital One-style: Transaction Date, Posted Date, Card No., Description, Category, Debit, Credit
        if (set.contains("transaction date") || set.contains("posted date")),
           set.contains("description"),
           set.contains("debit") || set.contains("credit")
        {
            return mapping(
                headers: normalizedHeaders,
                pairs: [
                    "transaction date": .postedDate,
                    "posted date": .postedDate,
                    "description": .description,
                    "category": .category,
                    "debit": .debit,
                    "credit": .credit,
                    "card no.": .ignore,
                    "card no": .ignore,
                ],
                preset: "Capital One"
            )
        }

        return nil
    }

    private static func mapping(
        headers: [String],
        pairs: [String: CSVImportColumn],
        preset: String
    ) -> CSVColumnMapping {
        var assignments: [Int: CSVImportColumn] = [:]
        var usedPostedDate = false
        for (index, header) in headers.enumerated() {
            guard let column = pairs[header] else { continue }
            if column == .postedDate {
                if usedPostedDate { continue }
                usedPostedDate = true
            }
            assignments[index] = column
        }
        return CSVColumnMapping(assignments: assignments, presetName: preset)
    }

    // MARK: - Synonyms

    private static func guessColumn(header: String, used: Set<CSVImportColumn>) -> CSVImportColumn? {
        let rules: [(CSVImportColumn, [String])] = [
            (.postedDate, [
                "posted_date", "posted date", "post date", "transaction date", "trans date",
                "date", "booking date", "value date",
            ]),
            (.amount, ["amount", "amt", "transaction amount", "sum"]),
            (.debit, ["debit", "withdrawal", "outflow", "expense"]),
            (.credit, ["credit", "deposit", "inflow", "payment"]),
            (.description, [
                "raw_description", "description", "memo", "payee", "name", "details",
                "transaction description", "narrative",
            ]),
            (.title, ["title", "merchant", "cleaned description"]),
            (.location, ["location", "city", "address"]),
            (.category, ["category", "type", "spending category"]),
            (.account, ["account", "account name", "account nickname"]),
            (.tags, ["tags", "labels"]),
            (.pending, ["pending", "status", "posted"]),
            (.currency, ["currency", "currency code", "curr"]),
            (.externalID, ["external_id", "external id", "id", "reference", "fitid", "transaction id"]),
        ]

        for (column, synonyms) in rules {
            guard !used.contains(column) else { continue }
            if synonyms.contains(header) { return column }
            // Fuzzy contains for longer headers
            if synonyms.contains(where: { header == $0 || header.hasPrefix($0 + " ") }) {
                return column
            }
        }
        return nil
    }

    static func normalize(_ header: String) -> String {
        header
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\"", with: "")
    }
}
