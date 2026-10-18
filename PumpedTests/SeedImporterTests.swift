import PumpedCore
import SwiftData
import XCTest
@testable import Pumped

@MainActor
final class SeedImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try PumpedStore.makeContainer(inMemory: true)
    }

    func testImportsBundledLibrary() throws {
        let library = try SeedImporter.bundledLibrary()
        XCTAssertTrue(try SeedImporter.importIfNeeded(library, into: context))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), library.exercises.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MovementType>()), library.movementTypes.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StretchSequence>()), library.stretchSequences.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RestTimerSettings>()), 1)

        let first = library.exercises[0]
        let exercise = try XCTUnwrap(fetchExercise(first.id))
        XCTAssertEqual(exercise.movementType?.id, first.movementType)
        XCTAssertEqual(Set(exercise.equipment.map(\.id)), Set(first.equipment))
        XCTAssertEqual(exercise.exerciseType, first.exerciseType)
    }

    func testSameVersionIsNotReimported() throws {
        let library = Self.library(version: 1)
        XCTAssertTrue(try SeedImporter.importIfNeeded(library, into: context))
        XCTAssertFalse(try SeedImporter.importIfNeeded(library, into: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    func testNewerVersionUpsertsAndKeepsUserState() throws {
        try SeedImporter.importIfNeeded(Self.library(version: 1), into: context)
        let exercise = try XCTUnwrap(fetchExercise("back-squat"))
        exercise.isLiked = true
        exercise.isHidden = true
        try context.save()

        var updated = Self.library(version: 2)
        updated.exercises[0].name = "High-Bar Back Squat"
        updated.stretchSequences[0].items.append(.init(stretch: "quad-stretch", durationSec: 45))
        XCTAssertTrue(try SeedImporter.importIfNeeded(updated, into: context))

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        let reloaded = try XCTUnwrap(fetchExercise("back-squat"))
        XCTAssertEqual(reloaded.name, "High-Bar Back Squat")
        XCTAssertTrue(reloaded.isLiked)
        XCTAssertTrue(reloaded.isHidden)

        let sequence = try XCTUnwrap(context.fetch(FetchDescriptor<StretchSequence>()).first)
        XCTAssertEqual(sequence.orderedItems.map(\.durationSec), [30, 45])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StretchItem>()), 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SeedState>()).first?.appliedVersion, 2)
    }

    private func fetchExercise(_ id: String) throws -> Exercise? {
        try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first
    }

    private static func library(version: Int) -> SeedLibrary {
        SeedLibrary(
            version: version,
            muscleGroups: [.init(id: "quads", name: "Quads")],
            equipment: [.init(id: "barbell", name: "Barbell")],
            movementTypes: [.init(id: "squat", name: "Squat", primaryMuscles: ["quads"])],
            exercises: [
                .init(id: "back-squat", name: "Back Squat", movementType: "squat",
                      equipment: ["barbell"], exerciseType: .heavyCompound, muscles: ["quads"]),
            ],
            cardioOptions: [.init(id: "bike", name: "Bike")],
            stretches: [.init(id: "quad-stretch", name: "Quad Stretch", defaultDurationSec: 30)],
            stretchSequences: [
                .init(id: "lower-body", name: "Lower Body", items: [.init(stretch: "quad-stretch", durationSec: 30)]),
            ]
        )
    }
}
