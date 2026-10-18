import SwiftData
import SwiftUI

@main
struct PumpedApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try PumpedStore.makeContainer()
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
