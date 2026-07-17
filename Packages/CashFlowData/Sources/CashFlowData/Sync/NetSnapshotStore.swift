import Foundation
import CashFlowKit

/// Small App Group snapshot for widgets (falls back to Application Support when group is unavailable).
public struct NetCashFlowSnapshot: Codable, Sendable, Equatable {
    public let net: Decimal
    public let incomeTotal: Decimal
    public let expenseTotal: Decimal
    public let rangeLabel: String
    public let updatedAt: Date

    public init(
        net: Decimal,
        incomeTotal: Decimal,
        expenseTotal: Decimal,
        rangeLabel: String,
        updatedAt: Date = .now
    ) {
        self.net = net
        self.incomeTotal = incomeTotal
        self.expenseTotal = expenseTotal
        self.rangeLabel = rangeLabel
        self.updatedAt = updatedAt
    }
}

public struct NetSnapshotStore: Sendable {
    public static let defaultAppGroupID = "group.com.expensetracking.shared"
    private let appGroupID: String
    private let fileName = "net_snapshot.json"

    public init(appGroupID: String = NetSnapshotStore.defaultAppGroupID) {
        self.appGroupID = appGroupID
    }

    public func save(_ snapshot: NetCashFlowSnapshot) throws {
        let url = try resolvedFileURL(createDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public func load() throws -> NetCashFlowSnapshot? {
        let url = try resolvedFileURL(createDirectories: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NetCashFlowSnapshot.self, from: data)
    }

    public func clear() throws {
        let url = try resolvedFileURL(createDirectories: false)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func resolvedFileURL(createDirectories: Bool) throws -> URL {
        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        {
            if createDirectories {
                try FileManager.default.createDirectory(
                    at: groupURL,
                    withIntermediateDirectories: true
                )
            }
            return groupURL.appendingPathComponent(fileName)
        }

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("CashFlow", isDirectory: true)
        if createDirectories {
            try FileManager.default.createDirectory(
                at: support,
                withIntermediateDirectories: true
            )
        }
        return support.appendingPathComponent(fileName)
    }
}
