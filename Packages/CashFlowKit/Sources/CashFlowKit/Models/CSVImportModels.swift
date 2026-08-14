import Foundation

/// Logical columns a CSV row can map into.
public enum CSVImportColumn: String, CaseIterable, Hashable, Sendable, Codable {
    case postedDate
    case amount
    case debit
    case credit
    case description
    case currency
    case category
    case account
    case tags
    case pending
    case location
    case title
    case externalID
    case ignore
}

/// User- or auto-detected mapping from CSV header index → logical column.
public struct CSVColumnMapping: Hashable, Sendable, Codable {
    /// Header index → column. Unmapped headers are omitted (ignored).
    public var assignments: [Int: CSVImportColumn]
    /// Detected preset name when a known format matched (e.g. "Cash Flow export").
    public var presetName: String?

    public init(assignments: [Int: CSVImportColumn] = [:], presetName: String? = nil) {
        self.assignments = assignments
        self.presetName = presetName
    }

    public func column(for headerIndex: Int) -> CSVImportColumn? {
        assignments[headerIndex]
    }

    public var hasPostedDate: Bool {
        assignments.values.contains(.postedDate)
    }

    public var hasAmount: Bool {
        assignments.values.contains(.amount)
            || (assignments.values.contains(.debit) && assignments.values.contains(.credit))
            || assignments.values.contains(.debit)
            || assignments.values.contains(.credit)
    }

    public var hasDescription: Bool {
        assignments.values.contains(.description) || assignments.values.contains(.title)
    }

    public var isReady: Bool {
        hasPostedDate && hasAmount && hasDescription
    }
}

/// One parsed data row before conflict resolution / commit.
public struct CSVImportRow: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let rowIndex: Int
    public let postedDate: Date
    public let amount: Decimal
    public let description: String
    public let currencyCode: String
    public let categoryName: String?
    public let tags: [String]
    public let isPending: Bool
    public let location: String?
    public let title: String?
    public let externalID: String?
    public let parseError: String?

    public init(
        id: String = UUID().uuidString,
        rowIndex: Int,
        postedDate: Date,
        amount: Decimal,
        description: String,
        currencyCode: String = "USD",
        categoryName: String? = nil,
        tags: [String] = [],
        isPending: Bool = false,
        location: String? = nil,
        title: String? = nil,
        externalID: String? = nil,
        parseError: String? = nil
    ) {
        self.id = id
        self.rowIndex = rowIndex
        self.postedDate = postedDate
        self.amount = amount
        self.description = description
        self.currencyCode = currencyCode
        self.categoryName = categoryName
        self.tags = tags
        self.isPending = isPending
        self.location = location
        self.title = title
        self.externalID = externalID
        self.parseError = parseError
    }

    public var isValid: Bool { parseError == nil }
}

public enum ImportConflictAction: String, Hashable, Sendable, Codable, CaseIterable {
    case skip
    case replace
    case keepBoth
}

/// Fingerprint used to detect duplicate transactions on the target account.
public struct TransactionFingerprint: Hashable, Sendable, Codable {
    public let accountID: AccountID
    public let dayKey: String
    public let amount: Decimal
    public let description: String

    public init(accountID: AccountID, postedDate: Date, amount: Decimal, description: String, calendar: Calendar = .current) {
        self.accountID = accountID
        let comps = calendar.dateComponents([.year, .month, .day], from: postedDate)
        self.dayKey = String(
            format: "%04d-%02d-%02d",
            comps.year ?? 0,
            comps.month ?? 0,
            comps.day ?? 0
        )
        self.amount = amount
        self.description = description
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public init(accountID: AccountID, dayKey: String, amount: Decimal, description: String) {
        self.accountID = accountID
        self.dayKey = dayKey
        self.amount = amount
        self.description = description
    }
}

public struct CSVImportConflict: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let importRow: CSVImportRow
    public let existingTransactionID: TransactionID
    public let existingDescription: String
    public let existingAmount: Decimal
    public let existingPostedDate: Date
    /// `nil` until the user chooses Skip / Replace / Keep both (or a bulk action).
    public var action: ImportConflictAction?

    public init(
        id: String = UUID().uuidString,
        importRow: CSVImportRow,
        existingTransactionID: TransactionID,
        existingDescription: String,
        existingAmount: Decimal,
        existingPostedDate: Date,
        action: ImportConflictAction? = nil
    ) {
        self.id = id
        self.importRow = importRow
        self.existingTransactionID = existingTransactionID
        self.existingDescription = existingDescription
        self.existingAmount = existingAmount
        self.existingPostedDate = existingPostedDate
        self.action = action
    }
}

public struct CSVImportPreview: Hashable, Sendable {
    public let headers: [String]
    public let mapping: CSVColumnMapping
    public let sampleRows: [[String]]
    public let rows: [CSVImportRow]
    public let validRowCount: Int
    public let invalidRowCount: Int

    public init(
        headers: [String],
        mapping: CSVColumnMapping,
        sampleRows: [[String]],
        rows: [CSVImportRow]
    ) {
        self.headers = headers
        self.mapping = mapping
        self.sampleRows = sampleRows
        self.rows = rows
        self.validRowCount = rows.filter(\.isValid).count
        self.invalidRowCount = rows.filter { !$0.isValid }.count
    }
}

public enum CSVImportAccountChoice: Hashable, Sendable {
    case existing(AccountID)
    case createNew(name: String, institutionName: String)
}

public struct CSVImportCommitPlan: Hashable, Sendable {
    public let fileName: String
    public let rows: [CSVImportRow]
    public let conflicts: [CSVImportConflict]
    public let accountChoice: CSVImportAccountChoice
    public let currencyCode: String

    public init(
        fileName: String,
        rows: [CSVImportRow],
        conflicts: [CSVImportConflict],
        accountChoice: CSVImportAccountChoice,
        currencyCode: String = "USD"
    ) {
        self.fileName = fileName
        self.rows = rows
        self.conflicts = conflicts
        self.accountChoice = accountChoice
        self.currencyCode = currencyCode
    }
}

public struct CSVImportCommitResult: Hashable, Sendable {
    public let batch: ImportBatch

    public init(batch: ImportBatch) {
        self.batch = batch
    }
}
