import Foundation

public struct ImportBatchID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ImportBatchStatus: String, Hashable, Sendable, Codable {
    case active
    case deleted
}

/// Durable record of a CSV import (including tombstones after batch delete).
public struct ImportBatch: Identifiable, Hashable, Sendable, Codable {
    public let id: ImportBatchID
    public let fileName: String
    public let importedAt: Date
    public let accountID: AccountID
    public let accountName: String
    public let createdAccount: Bool
    public let insertedCount: Int
    public let skippedCount: Int
    public let replacedCount: Int
    public let keepBothCount: Int
    public let status: ImportBatchStatus
    public let deletedAt: Date?

    public init(
        id: ImportBatchID,
        fileName: String,
        importedAt: Date,
        accountID: AccountID,
        accountName: String,
        createdAccount: Bool,
        insertedCount: Int,
        skippedCount: Int,
        replacedCount: Int,
        keepBothCount: Int = 0,
        status: ImportBatchStatus,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.importedAt = importedAt
        self.accountID = accountID
        self.accountName = accountName
        self.createdAccount = createdAccount
        self.insertedCount = insertedCount
        self.skippedCount = skippedCount
        self.replacedCount = replacedCount
        self.keepBothCount = keepBothCount
        self.status = status
        self.deletedAt = deletedAt
    }
}
