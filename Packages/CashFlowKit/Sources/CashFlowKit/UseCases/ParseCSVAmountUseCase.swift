import Foundation

/// Parses currency-like strings into `Decimal` (never Double).
public enum ParseCSVAmountUseCase: Sendable {
    public static func parse(_ raw: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var negative = false
        if text.hasPrefix("(") && text.hasSuffix(")") {
            negative = true
            text.removeFirst()
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("-") {
            negative = true
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("+") {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        text = text.replacingOccurrences(of: "$", with: "")
        text = text.replacingOccurrences(of: "€", with: "")
        text = text.replacingOccurrences(of: "£", with: "")
        text = text.replacingOccurrences(of: ",", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let value = Decimal(string: text) else { return nil }
        return negative ? -value : value
    }

    /// Combines optional debit/credit columns (expenses positive debit → negative amount).
    public static func fromDebitCredit(debit: String?, credit: String?) -> Decimal? {
        let debitValue = debit.flatMap(parse) ?? 0
        let creditValue = credit.flatMap(parse) ?? 0
        if debitValue == 0 && creditValue == 0 {
            if (debit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && (credit?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            {
                return nil
            }
            return 0
        }
        // Debit = money out (negative); credit = money in (positive).
        return creditValue - abs(debitValue)
    }
}

/// Tries common CSV date formats.
public enum ParseCSVDateUseCase: Sendable {
    private static let formats: [String] = [
        "yyyy-MM-dd",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss",
        "MM/dd/yyyy",
        "M/d/yyyy",
        "MM/dd/yy",
        "M/d/yy",
        "dd/MM/yyyy",
        "d/M/yyyy",
        "MMM d, yyyy",
        "MMMM d, yyyy",
        "dd-MMM-yyyy",
        "yyyy/MM/dd",
    ]

    public static func parse(_ raw: String, calendar: Calendar = .current) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.calendar = calendar

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return calendar.startOfDay(for: date)
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = iso.date(from: String(text.prefix(10))) {
            return calendar.startOfDay(for: date)
        }
        return nil
    }
}

/// Maps a CSV category name onto a system category when possible.
public enum MapCSVCategoryUseCase: Sendable {
    public static func categoryID(forName name: String?) -> CategoryID? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        for system in SystemCategory.allCases {
            if system.name.lowercased() == lower || system.rawValue.lowercased() == lower {
                return system.id
            }
        }
        // Common aliases
        let aliases: [String: SystemCategory] = [
            "food": .dining,
            "food & dining": .dining,
            "restaurants": .dining,
            "auto": .transport,
            "auto & transport": .transport,
            "gas": .transport,
            "utilities": .bills,
            "bills & utilities": .bills,
            "rent": .rentMortgage,
            "mortgage": .rentMortgage,
            "travel": .travelVacation,
            "health": .healthFitness,
            "fitness": .healthFitness,
            "fees": .feesCharges,
            "atm": .feesCharges,
            "paycheck": .income,
            "salary": .income,
            "transfer": .transfer,
            "payment": .creditCardPayment,
            "credit card payment": .creditCardPayment,
        ]
        if let mapped = aliases[lower] {
            return mapped.id
        }
        return nil
    }
}
