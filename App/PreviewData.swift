import SwiftData

/// In-memory store with the bundled library, for SwiftUI previews.
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let container = try! PumpedStore.makeContainer(inMemory: true)
        SeedImporter.importBundledSeedIfNeeded(into: container.mainContext)
        return container
    }()
}
