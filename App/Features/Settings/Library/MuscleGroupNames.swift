import Foundation

/// Display names for muscle group ids. Muscle groups aren't stored in SwiftData, so the names
/// come from the bundled seed.
@MainActor
enum MuscleGroupNames {
    private static let names: [String: String] = {
        let groups = (try? SeedImporter.bundledLibrary().muscleGroups) ?? []
        return Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }()

    static func name(for id: String) -> String {
        names[id] ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func list(_ ids: [String]) -> String {
        ids.map(name(for:)).joined(separator: ", ")
    }
}
