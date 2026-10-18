import Foundation
import XCTest
@testable import PumpedCore

final class SeedLibraryTests: XCTestCase {
    /// The real `App/Resources/seed.json`, so CI rejects a broken library before it ships.
    func testBundledSeedIsValid() throws {
        let library = try Self.bundledLibrary()
        XCTAssertGreaterThanOrEqual(library.version, 1)
        XCTAssertFalse(library.exercises.isEmpty)
        XCTAssertFalse(library.stretchSequences.isEmpty)
    }

    func testDecodesExerciseFields() throws {
        let json = """
        {
          "version": 1,
          "muscleGroups": [{ "id": "quads", "name": "Quads" }],
          "equipment": [{ "id": "barbell", "name": "Barbell" }],
          "movementTypes": [{ "id": "squat", "name": "Squat", "primaryMuscles": ["quads"] }],
          "exercises": [{ "id": "back-squat", "name": "Back Squat", "movementType": "squat",
                          "equipment": ["barbell"], "exerciseType": "heavyCompound", "muscles": ["quads"] }],
          "cardioOptions": [],
          "stretches": [],
          "stretchSequences": []
        }
        """
        let library = try SeedLibrary.load(from: Data(json.utf8))
        XCTAssertEqual(library.exercises.first?.exerciseType, .heavyCompound)
        XCTAssertEqual(library.exercises.first?.equipment, ["barbell"])
    }

    func testRejectsUnknownExerciseType() {
        let json = """
        { "version": 1, "muscleGroups": [], "equipment": [], "movementTypes": [],
          "exercises": [{ "id": "x", "name": "X", "movementType": "m", "equipment": [],
                          "exerciseType": "superHeavy", "muscles": [] }],
          "cardioOptions": [], "stretches": [], "stretchSequences": [] }
        """
        XCTAssertThrowsError(try SeedLibrary.decode(from: Data(json.utf8)))
    }

    func testValidLibraryHasNoIssues() {
        XCTAssertEqual(Self.validLibrary().issues(), [])
    }

    func testBodyweightExerciseNeedsNoEquipment() {
        var library = Self.validLibrary()
        library.exercises[0].equipment = []
        XCTAssertEqual(library.issues(), [])
    }

    func testFlagsUnknownReferences() {
        var library = Self.validLibrary()
        library.exercises[0].movementType = "lunge"
        library.exercises[0].equipment = ["barbell", "kettlebell"]
        library.exercises[0].muscles = ["quads", "calves"]
        library.stretchSequences[0].items.append(.init(stretch: "pigeon", durationSec: 30))

        let issues = Set(library.issues())
        XCTAssertTrue(issues.contains(.unknownMovementType(exercise: "back-squat", movementType: "lunge")))
        XCTAssertTrue(issues.contains(.unknownEquipment(exercise: "back-squat", equipment: "kettlebell")))
        XCTAssertTrue(issues.contains(.unknownMuscle(owner: "back-squat", muscle: "calves")))
        XCTAssertTrue(issues.contains(.unknownStretch(sequence: "lower-body", stretch: "pigeon")))
        // The squat movement type lost its only variation.
        XCTAssertTrue(issues.contains(.movementTypeWithoutVariations("squat")))
    }

    func testFlagsMovementTypeWithoutMusclesOrVariations() {
        var library = Self.validLibrary()
        library.movementTypes.append(.init(id: "lunge", name: "Lunge", primaryMuscles: []))
        XCTAssertEqual(
            Set(library.issues()),
            [.movementTypeWithoutMuscles("lunge"), .movementTypeWithoutVariations("lunge")]
        )
    }

    func testFlagsDuplicateAndEmptyFields() {
        var library = Self.validLibrary()
        library.equipment.append(.init(id: "barbell", name: "Another Barbell"))
        library.cardioOptions.append(.init(id: "", name: "Nameless"))
        library.stretches.append(.init(id: "hold", name: "  ", defaultDurationSec: 0))
        XCTAssertEqual(
            Set(library.issues()),
            [
                .duplicateID(kind: "equipment", id: "barbell"),
                .emptyID(kind: "cardio option"),
                .emptyName(kind: "stretch", id: "hold"),
                .nonPositiveDuration(owner: "hold"),
            ]
        )
    }

    func testFlagsEmptySequenceAndBadVersion() {
        var library = Self.validLibrary()
        library.version = 0
        library.stretchSequences[0].items = []
        XCTAssertEqual(Set(library.issues()), [.unsupportedVersion(0), .emptyStretchSequence("lower-body")])
    }

    func testValidateThrowsAllIssues() {
        var library = Self.validLibrary()
        library.exercises[0].muscles = []
        library.exercises[0].movementType = "nope"
        XCTAssertThrowsError(try library.validate()) { error in
            let issues = (error as? SeedValidationError)?.issues ?? []
            XCTAssertTrue(issues.contains(.exerciseWithoutMuscles("back-squat")))
            XCTAssertTrue(issues.contains(.unknownMovementType(exercise: "back-squat", movementType: "nope")))
        }
    }

    func testExerciseTypeDefaultRest() {
        XCTAssertEqual(ExerciseType.heavyCompound.defaultRestSeconds, 180)
        XCTAssertEqual(ExerciseType.compound.defaultRestSeconds, 120)
        XCTAssertEqual(ExerciseType.isolation.defaultRestSeconds, 60)
    }

    /// Loads and validates the real `App/Resources/seed.json`.
    static func bundledLibrary() throws -> SeedLibrary {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PumpedCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PumpedCore
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("App/Resources/seed.json")
        return try SeedLibrary.load(from: Data(contentsOf: url))
    }

    static func validLibrary() -> SeedLibrary {
        SeedLibrary(
            version: 1,
            muscleGroups: [.init(id: "quads", name: "Quads"), .init(id: "glutes", name: "Glutes")],
            equipment: [.init(id: "barbell", name: "Barbell")],
            movementTypes: [.init(id: "squat", name: "Squat", primaryMuscles: ["quads", "glutes"])],
            exercises: [
                .init(id: "back-squat", name: "Back Squat", movementType: "squat",
                      equipment: ["barbell"], exerciseType: .heavyCompound, muscles: ["quads", "glutes"]),
            ],
            cardioOptions: [.init(id: "bike", name: "Bike")],
            stretches: [.init(id: "quad-stretch", name: "Quad Stretch", defaultDurationSec: 30)],
            stretchSequences: [
                .init(id: "lower-body", name: "Lower Body", items: [.init(stretch: "quad-stretch", durationSec: 30)]),
            ]
        )
    }
}
