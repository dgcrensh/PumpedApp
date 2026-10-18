import SwiftData

/// Ordered list of every schema version the store has had. Add new versions and stages here.
enum PumpedMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PumpedSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum PumpedStore {
    /// Builds the app's container. `inMemory` is for tests and previews.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PumpedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: schema,
            migrationPlan: PumpedMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
