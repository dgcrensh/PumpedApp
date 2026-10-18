import XCTest
@testable import PumpedCore

final class VariationSelectorTests: XCTestCase {
    private func candidateIDs(_ selector: VariationSelector, _ movement: String, excluding: Set<String> = []) -> [String] {
        selector.weightedCandidates(for: movement, excluding: excluding).map(\.id)
    }

    // MARK: Filtering

    func testCandidatesAreTheMovementTypesExercises() {
        XCTAssertEqual(candidateIDs(Fixture.selector(), "squat"), ["back-squat", "goblet-squat", "leg-press"])
    }

    func testHiddenExercisesAreExcluded() {
        let selector = Fixture.selector { $0.update("goblet-squat") { $0.isHidden = true } }
        XCTAssertEqual(candidateIDs(selector, "squat"), ["back-squat", "leg-press"])
    }

    func testExercisesNeedingAnyUnavailableEquipmentAreExcluded() {
        // Back squat needs barbell + rack; losing just the rack excludes it.
        XCTAssertEqual(candidateIDs(Fixture.selector(unavailable: ["rack"]), "squat"), ["goblet-squat", "leg-press"])
    }

    func testBodyweightExercisesSurviveAnyUnavailableEquipment() {
        let selector = Fixture.selector(unavailable: ["barbell", "dumbbells", "bench"])
        XCTAssertEqual(candidateIDs(selector, "press"), ["push-up"])
    }

    func testExercisesAlreadyInTheStackAreExcluded() {
        XCTAssertEqual(candidateIDs(Fixture.selector(), "squat", excluding: ["back-squat"]), ["goblet-squat", "leg-press"])
    }

    // MARK: Weighting

    func testBaseWeightIsOne() {
        let selector = Fixture.selector()
        XCTAssertEqual(selector.weightedCandidates(for: "squat", excluding: []).map(\.weight), [1, 1, 1])
    }

    func testLikeBoost() {
        let selector = Fixture.selector { $0.update("leg-press") { $0.isLiked = true } }
        XCTAssertEqual(selector.weight(of: selector.exercise("leg-press")!), 2.0)
    }

    func testFamiliarityBoostAndRepeatDamping() {
        // Newest first: last workout did goblet squat, the one before did back squat.
        let history = SelectionHistory(workoutsByMovementType: ["squat": [["goblet-squat"], ["back-squat"]]])
        let selector = Fixture.selector(history: history)
        XCTAssertEqual(selector.weight(of: selector.exercise("back-squat")!), 1.5)
        XCTAssertEqual(selector.weight(of: selector.exercise("goblet-squat")!), 1.5 * 0.75, accuracy: 1e-9)
        XCTAssertEqual(selector.weight(of: selector.exercise("leg-press")!), 1.0)
    }

    func testFamiliarityOnlyCountsTheWindow() {
        let old = Array(repeating: Set(["goblet-squat"]), count: SelectionTuning.default.familiarityWindow)
        let history = SelectionHistory(workoutsByMovementType: ["squat": old + [["back-squat"]]])
        let selector = Fixture.selector(history: history)
        XCTAssertEqual(selector.weight(of: selector.exercise("back-squat")!), 1.0)
    }

    func testBoostsCompound() {
        let history = SelectionHistory(workoutsByMovementType: ["squat": [["leg-press"]]])
        let selector = Fixture.selector(history: history) { $0.update("leg-press") { $0.isLiked = true } }
        XCTAssertEqual(selector.weight(of: selector.exercise("leg-press")!), 2.0 * 1.5 * 0.75, accuracy: 1e-9)
    }

    func testWeightingShiftsPickFrequency() {
        var selector = Fixture.selector { $0.update("leg-press") { $0.isLiked = true } }
        selector.tuning.likeBoost = 8
        var rng = SeededGenerator(seed: 7)
        var counts: [String: Int] = [:]
        for _ in 0..<2_000 {
            counts[selector.select(for: "squat", excluding: [], using: &rng).exerciseID!, default: 0] += 1
        }
        // Expected share 8/10 for leg press, 1/10 for each of the others.
        XCTAssertGreaterThan(counts["leg-press"]!, 1_450)
        XCTAssertGreaterThan(counts["back-squat"]!, 100)
        XCTAssertGreaterThan(counts["goblet-squat"]!, 100)
    }

    func testZeroWeightIsNeverPicked() {
        var selector = Fixture.selector { $0.update("leg-press") { $0.isLiked = true } }
        selector.tuning.likeBoost = 0
        var rng = SeededGenerator(seed: 1)
        for _ in 0..<500 {
            XCTAssertNotEqual(selector.select(for: "squat", excluding: [], using: &rng).exerciseID, "leg-press")
        }
    }

    // MARK: Fallback

    func testFallsBackToSameMuscleSubstituteWhenExhausted() {
        let selector = Fixture.selector()
        var rng = SeededGenerator(seed: 3)
        let fill = selector.select(for: "squat", excluding: ["back-squat", "goblet-squat", "leg-press"], using: &rng)
        XCTAssertTrue(fill.isSubstitute)
        XCTAssertTrue(["split-squat", "walking-lunge"].contains(fill.exerciseID))
    }

    func testSubstitutePoolIsFilteredToo() {
        let selector = Fixture.selector(unavailable: ["barbell", "leg-press", "dumbbells"])
        var rng = SeededGenerator(seed: 3)
        XCTAssertEqual(selector.select(for: "squat", excluding: [], using: &rng), .substitute(exerciseID: "walking-lunge"))
    }

    func testSubstitutesComeOnlyFromOtherMovementTypes() {
        let selector = Fixture.selector()
        XCTAssertEqual(selector.weightedSubstitutes(for: "squat", excluding: []).map(\.id), ["split-squat", "walking-lunge"])
        XCTAssertEqual(selector.weightedSubstitutes(for: "curl", excluding: []).map(\.id), [])
    }

    func testNoAvailableVariationWhenBothPoolsAreEmpty() {
        let selector = Fixture.selector { $0.update("barbell-curl") { $0.isHidden = true } }
        var rng = SeededGenerator(seed: 3)
        XCTAssertEqual(selector.select(for: "curl", excluding: [], using: &rng), .unavailable)
        XCTAssertEqual(selector.select(for: "unknown-movement", excluding: [], using: &rng), .unavailable)
    }

    // MARK: Determinism

    func testSameSeedGivesSamePicks() {
        let selector = Fixture.selector()
        func run(_ seed: UInt64) -> [String?] {
            var rng = SeededGenerator(seed: seed)
            return (0..<50).map { _ in selector.select(for: "press", excluding: [], using: &rng).exerciseID }
        }
        XCTAssertEqual(run(42), run(42))
        XCTAssertNotEqual(run(42), run(43))
    }

    func testPickDoesNotDependOnInputOrder() {
        let forward = Fixture.selector()
        let reversed = VariationSelector(exercises: Fixture.exercises.reversed(), movementTypes: Fixture.movementTypes)
        var a = SeededGenerator(seed: 9), b = SeededGenerator(seed: 9)
        for _ in 0..<50 {
            XCTAssertEqual(forward.select(for: "squat", excluding: [], using: &a), reversed.select(for: "squat", excluding: [], using: &b))
        }
    }

    // MARK: Seed library

    func testEveryBundledMovementTypeGetsAVariation() throws {
        let library = try SeedLibraryTests.bundledLibrary()
        let selector = VariationSelector(
            exercises: library.exercises.map { SelectionExercise($0) },
            movementTypes: library.movementTypes.map(SelectionMovementType.init)
        )
        var rng = SeededGenerator(seed: 0)
        for movement in library.movementTypes {
            let fill = selector.select(for: movement.id, excluding: [], using: &rng)
            guard case .variation(let id) = fill else { return XCTFail("\(movement.id): \(fill)") }
            XCTAssertEqual(selector.exercise(id)?.movementType, movement.id)
        }
    }
}
