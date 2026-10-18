import SwiftData
import SwiftUI

@main
struct PumpedApp: App {
    let container: ModelContainer

    init() {
        // UI tests start from a fresh in-memory store so runs don't see each other's data.
        let inMemory = CommandLine.arguments.contains("-ui-testing-reset-store")
        do {
            container = try PumpedStore.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Could not open the Pumped data store: \(error)")
        }
        SeedImporter.importBundledSeedIfNeeded(into: container.mainContext)
        if inMemory, CommandLine.arguments.contains("-ui-testing-sample-split") {
            UITestingData.addSampleSplit(to: container.mainContext)
        }
        if inMemory, CommandLine.arguments.contains("-ui-testing-sample-history") {
            UITestingData.addSampleHistory(to: container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
