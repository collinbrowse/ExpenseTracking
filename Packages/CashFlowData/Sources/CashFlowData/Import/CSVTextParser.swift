import Foundation
import CashFlowKit

/// Minimal RFC4180-ish CSV splitter (quotes, commas, CRLF).
enum CSVTextParser {
    struct Table: Sendable {
        let headers: [String]
        let rows: [[String]]
    }

    static func parse(_ data: Data) throws -> Table {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            throw CashFlowError.csvImport(message: "Couldn't read the CSV file as text.")
        }
        let lines = splitRecords(text)
        guard let headerLine = lines.first, !headerLine.isEmpty else {
            throw CashFlowError.csvImport(message: "The CSV file is empty.")
        }
        let headers = parseFields(headerLine)
        guard !headers.isEmpty else {
            throw CashFlowError.csvImport(message: "The CSV file has no header row.")
        }
        let rows = lines.dropFirst().map(parseFields).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return Table(headers: headers, rows: rows)
    }

    private static func splitRecords(_ text: String) -> [String] {
        var records: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                inQuotes.toggle()
                current.append(c)
                i += 1
                continue
            }
            if !inQuotes && (c == "\n" || c == "\r") {
                if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" {
                    i += 1
                }
                records.append(current)
                current = ""
                i += 1
                continue
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty || !records.isEmpty {
            records.append(current)
        }
        return records.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func parseFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                current.append(c)
                i += 1
                continue
            }
            if c == "\"" {
                inQuotes = true
                i += 1
                continue
            }
            if c == "," {
                fields.append(current)
                current = ""
                i += 1
                continue
            }
            current.append(c)
            i += 1
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

enum CSVRowMapper {
    static func mapRows(
        headers: [String],
        rawRows: [[String]],
        mapping: CSVColumnMapping
    ) -> [CSVImportRow] {
        rawRows.enumerated().map { index, cells in
            mapRow(rowIndex: index + 2, cells: cells, mapping: mapping)
        }
    }

    private static func mapRow(
        rowIndex: Int,
        cells: [String],
        mapping: CSVColumnMapping
    ) -> CSVImportRow {
        func value(_ column: CSVImportColumn) -> String? {
            guard let index = mapping.assignments.first(where: { $0.value == column })?.key,
                  index < cells.count
            else { return nil }
            let text = cells[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        var error: String?

        let dateRaw = value(.postedDate)
        let postedDate = dateRaw.flatMap { ParseCSVDateUseCase.parse($0) }
        if postedDate == nil {
            error = "Row \(rowIndex): invalid or missing date."
        }

        let amount: Decimal?
        if let amountRaw = value(.amount) {
            amount = ParseCSVAmountUseCase.parse(amountRaw)
            if amount == nil {
                error = error ?? "Row \(rowIndex): invalid amount."
            }
        } else {
            amount = ParseCSVAmountUseCase.fromDebitCredit(debit: value(.debit), credit: value(.credit))
            if amount == nil {
                error = error ?? "Row \(rowIndex): missing amount."
            }
        }

        let description = value(.description) ?? value(.title) ?? ""
        if description.isEmpty {
            error = error ?? "Row \(rowIndex): missing description."
        }

        let pendingRaw = value(.pending)?.lowercased()
        let isPending: Bool = {
            guard let pendingRaw else { return false }
            if ["1", "true", "yes", "pending"].contains(pendingRaw) { return true }
            if ["0", "false", "no", "posted", "cleared"].contains(pendingRaw) { return false }
            return false
        }()

        let tags = (value(.tags) ?? "")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return CSVImportRow(
            rowIndex: rowIndex,
            postedDate: postedDate ?? .distantPast,
            amount: amount ?? 0,
            description: description,
            currencyCode: value(.currency) ?? "USD",
            categoryName: value(.category),
            tags: tags,
            isPending: isPending,
            location: value(.location),
            title: value(.title),
            externalID: value(.externalID),
            parseError: error
        )
    }
}
