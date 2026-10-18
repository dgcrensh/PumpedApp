import XCTest
@testable import PumpedCore

/// Coverage checks on the shipped library (implementation plan M2), beyond the structural
/// validation in `SeedLibrary.validate()`.
final class BundledLibraryContentTests: XCTestCase {
    private var library: SeedLibrary!

    override func setUpWithError() throws {
        library = try SeedLibraryTests.bundledLibrary()
    }

    func testMovementTypesCoverTheSpec() {
        let ids = Set(library.movementTypes.map(\.id))
        XCTAssertTrue((12...16).contains(ids.count), "expected 12–16 movement types, got \(ids.count)")
        // The movement types spec §3 names.
        let named: Set = [
            "squat", "hip-hinge", "lunge", "horizontal-press", "vertical-press", "horizontal-row",
            "vertical-pull", "biceps-curl", "triceps-extension", "lateral-raise", "calf-raise", "core-flexion",
        ]
        XCTAssertEqual(named.subtracting(ids), [])
    }

    func testEveryMovementTypeHasThreeToSixVariations() {
        let counts = Dictionary(grouping: library.exercises, by: \.movementType).mapValues(\.count)
        for movement in library.movementTypes {
            let count = counts[movement.id] ?? 0
            XCTAssertTrue((3...6).contains(count), "\(movement.id) has \(count) variations")
        }
    }

    /// The down-swipe refills a slot with a variation that avoids the unavailable equipment,
    /// so every movement type needs variations on more than one kind of equipment.
    func testEveryMovementTypeSpansEquipment() {
        let byMovement = Dictionary(grouping: library.exercises, by: \.movementType)
        for movement in library.movementTypes {
            let setups = Set((byMovement[movement.id] ?? []).map { Set($0.equipment) })
            XCTAssertGreaterThan(setups.count, 1, "\(movement.id) uses a single equipment setup")
            for item in Set(setups.flatMap { $0 }) {
                XCTAssertTrue(
                    setups.contains { !$0.contains(item) },
                    "every \(movement.id) variation needs '\(item)'"
                )
            }
        }
    }

    /// The substitute fallback (spec §7) matches on primary muscles, so each variation should
    /// train at least one of its movement type's primary muscles.
    func testExercisesHitTheirMovementTypesPrimaryMuscles() {
        let primary = Dictionary(uniqueKeysWithValues: library.movementTypes.map { ($0.id, Set($0.primaryMuscles)) })
        for exercise in library.exercises {
            XCTAssertFalse(
                primary[exercise.movementType, default: []].isDisjoint(with: exercise.muscles),
                "\(exercise.id) shares no primary muscle with \(exercise.movementType)"
            )
        }
    }

    func testEveryExerciseTypeAndBodyweightOptionIsPresent() {
        XCTAssertEqual(Set(library.exercises.map(\.exerciseType)), Set(ExerciseType.allCases))
        XCTAssertTrue(library.exercises.contains { $0.equipment.isEmpty }, "no bodyweight exercises")
    }

    func testEveryMuscleGroupAndEquipmentIsUsed() {
        let usedMuscles = Set(library.exercises.flatMap(\.muscles) + library.movementTypes.flatMap(\.primaryMuscles))
        XCTAssertEqual(Set(library.muscleGroups.map(\.id)).subtracting(usedMuscles), [])
        XCTAssertEqual(Set(library.equipment.map(\.id)).subtracting(library.exercises.flatMap(\.equipment)), [])
    }

    func testCardioCoversTheSpec() {
        let ids = Set(library.cardioOptions.map(\.id))
        XCTAssertEqual(Set(["treadmill", "bike", "rower", "elliptical", "stairs"]).subtracting(ids), [])
    }

    func testStretchesAndDefaultSequences() {
        XCTAssertGreaterThanOrEqual(library.stretches.count, 20)
        XCTAssertEqual(
            Set(library.stretchSequences.map(\.name)),
            ["Upper Body", "Lower Body", "Full Body"]
        )
        for sequence in library.stretchSequences {
            XCTAssertGreaterThanOrEqual(sequence.items.count, 5, "\(sequence.id) is too short")
            XCTAssertEqual(Set(sequence.items.map(\.stretch)).count, sequence.items.count, "\(sequence.id) repeats a stretch")
        }
    }
}
