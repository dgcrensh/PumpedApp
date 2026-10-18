import Foundation

/// Display names for muscle group ids. Muscle groups aren't stored in SwiftData, so the names
/// come from the bundled seed.
@MainActor
enum MuscleGroupNames {
    /// Every muscle group in seed order, for pickers.
    static let all: [MuscleGroup] = ((try? SeedImporter.bundledLibrary().muscleGroups) ?? []).map { MuscleGroup(id: $0.id, name: $0.name) }

    private static let names: [String: String] = Dictionary(all.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

    static func name(for id: String) -> String {
        names[id] ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func list(_ ids: [String]) -> String {
        ids.map(name(for:)).joined(separator: ", ")
    }
}

struct MuscleGroup: Identifiable, Hashable {
    let id: String
    let name: String
}
