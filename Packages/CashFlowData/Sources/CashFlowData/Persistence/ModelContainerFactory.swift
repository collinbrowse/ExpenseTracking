import Foundation
import SwiftData

public enum ModelContainerFactory {
    public static func make(
        inMemory: Bool = false,
        appGroupID: String? = nil
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CashFlowSchemaV1.self)

        if inMemory {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(
                for: schema,
                migrationPlan: CashFlowMigrationPlan.self,
                configurations: [configuration]
            )
        }

        if let appGroupID {
            do {
                let configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    groupContainer: .identifier(appGroupID)
                )
                return try ModelContainer(
                    for: schema,
                    migrationPlan: CashFlowMigrationPlan.self,
                    configurations: [configuration]
                )
            } catch {
                // App Group may be unavailable without a paid team provisioning profile.
            }
        }

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(
            for: schema,
            migrationPlan: CashFlowMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
