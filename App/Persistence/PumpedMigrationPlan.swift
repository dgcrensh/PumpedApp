import Foundation
import SwiftData

/// Ordered list of every schema version the store has had. Add new versions and stages here.
enum PumpedMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PumpedSchemaV1.self, PumpedSchemaV2.self, PumpedSchemaV3.self] }

    static var stages: [MigrationStage] {
        [
            // Adds `WorkoutEntry.movementTypeID` (optional, so existing rows read nil).
            .lightweight(fromVersion: PumpedSchemaV1.self, toVersion: PumpedSchemaV2.self),
            // Adds `MovementSlot.pinnedExercise` (optional, so existing slots stay unpinned).
            .lightweight(fromVersion: PumpedSchemaV2.self, toVersion: PumpedSchemaV3.self),
        ]
    }
}

enum PumpedStore {
    /// Builds the app's container at the default location, or in memory for tests and previews.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PumpedSchemaV3.self)
        return try makeContainer(ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
    }

    /// Builds a container backed by the store file at `url`. Tests use it to reopen a store the way
    /// a relaunch does.
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PumpedSchemaV3.self)
        return try makeContainer(ModelConfiguration(schema: schema, url: url))
    }

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: PumpedSchemaV3.self),
            migrationPlan: PumpedMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
