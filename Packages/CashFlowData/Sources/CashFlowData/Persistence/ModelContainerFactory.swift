import Foundation
import SwiftData
import os

public enum ModelContainerFactory {
    private static let logger = Logger(subsystem: "com.expensetracking", category: "persistence")

    /// Creates the app ModelContainer. Disk failures wipe stores and retry; last resort is in-memory.
    /// Prefer this over crashing the process when SwiftData cannot migrate.
    public static func make(
        inMemory: Bool = false,
        appGroupID: String? = nil
    ) throws -> ModelContainer {
        if inMemory {
            return try makeInMemoryContainer()
        }
        return makeResilient(appGroupID: appGroupID)
    }

    /// Non-throwing entry point for app launch.
    public static func makeResilient(appGroupID: String? = nil) -> ModelContainer {
        let schema = Schema(versionedSchema: CashFlowSchemaV1.self)

        if let appGroupID {
            if let container = attemptLoad(schema: schema, configuration: appGroupConfiguration(schema: schema, appGroupID: appGroupID)) {
                return container
            }
            logger.error("App Group store failed to load; wiping and retrying")
            destroyPersistentStores(appGroupID: appGroupID)
            if let container = attemptLoad(schema: schema, configuration: appGroupConfiguration(schema: schema, appGroupID: appGroupID)) {
                return container
            }
            logger.error("App Group store still unavailable after wipe; falling back to local Application Support")
        }

        if let container = attemptLoad(schema: schema, configuration: localConfiguration(schema: schema)) {
            return container
        }
        logger.error("Local store failed to load; wiping and retrying")
        destroyPersistentStores(appGroupID: nil)
        if let container = attemptLoad(schema: schema, configuration: localConfiguration(schema: schema)) {
            return container
        }

        logger.fault("Persistent stores unusable; launching with in-memory SwiftData")
        do {
            return try makeInMemoryContainer()
        } catch {
            // In-memory failure is effectively impossible; keep a typed escape hatch for tests.
            preconditionFailure("In-memory ModelContainer failed: \(error)")
        }
    }

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CashFlowSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: CashFlowMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func attemptLoad(
        schema: Schema,
        configuration: ModelConfiguration
    ) -> ModelContainer? {
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: CashFlowMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            logger.error("ModelContainer load failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func appGroupConfiguration(schema: Schema, appGroupID: String) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(appGroupID)
        )
    }

    private static func localConfiguration(schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    }

    /// Removes SwiftData/SQLite store files from App Group + local Application Support.
    public static func destroyPersistentStores(appGroupID: String?) {
        let fm = FileManager.default
        for directory in storeDirectories(appGroupID: appGroupID) {
            deleteStoreArtifacts(in: directory, fileManager: fm)
        }
    }

    static func storeDirectories(appGroupID: String?) -> [URL] {
        var directories: [URL] = []
        if let appGroupID,
           let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        {
            // SwiftData with groupContainer writes under Library/Application Support.
            directories.append(root.appending(path: "Library/Application Support", directoryHint: .isDirectory))
            directories.append(root)
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            directories.append(appSupport)
        }
        var seen = Set<String>()
        return directories.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private static func deleteStoreArtifacts(in directory: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: directory.path) else { return }

        let knownBases = ["default.store", "default.sqlite", "CashFlow.store"]
        for base in knownBases {
            let baseURL = directory.appending(path: base)
            removeSQLiteBundle(at: baseURL, fileManager: fm)
        }

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            let name = url.lastPathComponent
            let isStore = name.hasSuffix(".store")
                || name.contains(".store-")
                || name.hasSuffix(".sqlite")
                || name.contains(".sqlite-")
            if isStore {
                removeSQLiteBundle(at: url, fileManager: fm)
            }
        }
    }

    private static func removeSQLiteBundle(at url: URL, fileManager fm: FileManager) {
        let path = url.path
        // SwiftData uses `default.store`; SQLite sidecars are typically `default.store-wal`.
        for candidate in [path, path + "-shm", path + "-wal", path + ".shm", path + ".wal"] {
            if fm.fileExists(atPath: candidate) {
                try? fm.removeItem(at: URL(fileURLWithPath: candidate))
            }
        }
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(at: url)
        }
    }
}
