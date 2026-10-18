import Foundation
import OSLog
import PumpedCore
import SwiftData

/// Imports the bundled exercise library into SwiftData.
///
/// Rows are matched by their stable seed `id`, so importing a newer seed updates names,
/// equipment and muscles in place while keeping user state (likes, hidden flags, history).
/// Rows dropped from the seed are left alone because workout history may reference them.
@MainActor
enum SeedImporter {
    private static let logger = Logger(subsystem: "com.dgcrensh.pumped", category: "Seed")

    /// Decodes and validates `seed.json` from the bundle.
    static func bundledLibrary(in bundle: Bundle = .main) throws -> SeedLibrary {
        guard let url = bundle.url(forResource: "seed", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try SeedLibrary.load(from: Data(contentsOf: url))
    }

    /// Imports the bundled seed if this store hasn't seen its version yet. Called on launch.
    static func importBundledSeedIfNeeded(into context: ModelContext) {
        do {
            try importIfNeeded(bundledLibrary(), into: context)
        } catch {
            logger.error("Seed import failed: \(String(describing: error), privacy: .public)")
            assertionFailure("Seed import failed: \(error)")
        }
    }

    /// Upserts `library` unless a seed with the same or a newer version was already applied.
    /// Returns whether an import ran.
    @discardableResult
    static func importIfNeeded(_ library: SeedLibrary, into context: ModelContext) throws -> Bool {
        let state = try context.fetch(FetchDescriptor<SeedState>()).first
        if let state, state.appliedVersion >= library.version { return false }
        try upsert(library, into: context)
        if let state {
            state.appliedVersion = library.version
        } else {
            context.insert(SeedState(appliedVersion: library.version))
        }
        if try context.fetch(FetchDescriptor<RestTimerSettings>()).isEmpty {
            context.insert(RestTimerSettings())
        }
        try context.save()
        logger.info("Imported seed version \(library.version)")
        return true
    }

    static func upsert(_ library: SeedLibrary, into context: ModelContext) throws {
        try library.validate()

        var equipment = try existing(Equipment.self, in: context)
        for seed in library.equipment {
            let row = fetchOrInsert(seed.id, in: &equipment, context: context) { Equipment(id: seed.id, name: seed.name) }
            row.name = seed.name
        }

        var movementTypes = try existing(MovementType.self, in: context)
        for seed in library.movementTypes {
            let row = fetchOrInsert(seed.id, in: &movementTypes, context: context) { MovementType(id: seed.id, name: seed.name) }
            row.name = seed.name
            row.primaryMuscles = seed.primaryMuscles
        }

        var exercises = try existing(Exercise.self, in: context)
        for seed in library.exercises {
            let row = fetchOrInsert(seed.id, in: &exercises, context: context) { Exercise(id: seed.id, name: seed.name, exerciseType: seed.exerciseType) }
            row.name = seed.name
            row.movementType = movementTypes[seed.movementType]
            row.equipment = seed.equipment.compactMap { equipment[$0] }
            row.exerciseType = seed.exerciseType
            row.muscles = seed.muscles
            row.isCustom = false
        }

        var cardio = try existing(CardioOption.self, in: context)
        for seed in library.cardioOptions {
            let row = fetchOrInsert(seed.id, in: &cardio, context: context) { CardioOption(id: seed.id, name: seed.name) }
            row.name = seed.name
        }

        var stretches = try existing(Stretch.self, in: context)
        for seed in library.stretches {
            let row = fetchOrInsert(seed.id, in: &stretches, context: context) { Stretch(id: seed.id, name: seed.name, defaultDurationSec: seed.defaultDurationSec) }
            row.name = seed.name
            row.defaultDurationSec = seed.defaultDurationSec
            row.isCustom = false
        }

        var sequences = try existing(StretchSequence.self, in: context)
        for seed in library.stretchSequences {
            let row = fetchOrInsert(seed.id, in: &sequences, context: context) { StretchSequence(id: seed.id, name: seed.name, isDefault: true) }
            row.name = seed.name
            row.isDefault = true
            // Default sequences are read-only, so their items are simply replaced.
            for item in row.items { context.delete(item) }
            row.items = seed.items.enumerated().map { offset, item in
                StretchItem(stretch: stretches[item.stretch], durationSec: item.durationSec, order: offset)
            }
        }
    }

    private static func existing<Model: PersistentModel & SeedKeyed>(
        _ type: Model.Type,
        in context: ModelContext
    ) throws -> [String: Model] {
        let rows = try context.fetch(FetchDescriptor<Model>())
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func fetchOrInsert<Model: PersistentModel & SeedKeyed>(
        _ id: String,
        in index: inout [String: Model],
        context: ModelContext,
        make: () -> Model
    ) -> Model {
        if let row = index[id] { return row }
        let row = make()
        context.insert(row)
        index[id] = row
        return row
    }
}

/// Models whose rows are keyed by a stable string id.
protocol SeedKeyed {
    var id: String { get }
}

extension Equipment: SeedKeyed {}
extension MovementType: SeedKeyed {}
extension Exercise: SeedKeyed {}
extension CardioOption: SeedKeyed {}
extension Stretch: SeedKeyed {}
extension StretchSequence: SeedKeyed {}
