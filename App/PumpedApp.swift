import SwiftData
import SwiftUI

@main
struct PumpedApp: App {
    let container: ModelContainer

    init() {
        do {
            // UI tests start from a fresh in-memory store so runs don't see each other's data.
            let inMemory = CommandLine.arguments.contains("-ui-testing-reset-store")
            container = try PumpedStore.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Could not open the Pumped data store: \(error)")
        }
        SeedImporter.importBundledSeedIfNeeded(into: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
