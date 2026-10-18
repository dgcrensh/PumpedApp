import Foundation
import XCTest
@testable import PumpedCore

final class FakeHistoryTests: XCTestCase {
    private let end = Date(timeIntervalSince1970: 1_790_000_000)
    private let days = [["squat", "lunge"], ["press", "curl"]]
    private let types: [String: ExerciseType] = [
        "back-squat": .heavyCompound, "bench-press": .heavyCompound,
        "barbell-curl": .isolation, "goblet-squat": .compound,
    ]

    private func generate(
        seed: UInt64 = 1,
        days: [[String]]? = nil,
        selector: VariationSelector = Fixture.selector(),
        weeks: Int = 26
    ) -> [FakeHistory.Workout] {
        var rng = SeededGenerator(seed: seed)
        return FakeHistory.generate(days: days ?? self.days, selector: selector, exerciseTypes: types, endingAt: end, weeks: weeks, using: &rng)
    }

    func testSixMonthsOfWorkoutsWalkingTheSplitInOrder() {
        let workouts = generate()
        XCTAssertEqual(workouts.count, 26 * 4)
        XCTAssertEqual(workouts.map(\.dayIndex).prefix(4), [0, 1, 0, 1])
        let first = try! XCTUnwrap(workouts.first)
        XCTAssertGreaterThan(first.startedAt, end.addingTimeInterval(-26 * 7 * 86_400))
        XCTAssertEqual(workouts.map(\.startedAt), workouts.map(\.startedAt).sorted(), "oldest first")
        for workout in workouts {
            XCTAssertLessThan(workout.startedAt, workout.endedAt)
            XCTAssertLessThanOrEqual(workout.endedAt, end)
            let sets = workout.entries.flatMap(\.sets)
            XCTAssertEqual(sets.map(\.loggedAt), sets.map(\.loggedAt).sorted())
            XCTAssertTrue(sets.allSatisfy { $0.loggedAt > workout.startedAt && $0.loggedAt < workout.endedAt })
        }
    }

    func testSameSeedSameHistory() {
        XCTAssertEqual(generate(seed: 9), generate(seed: 9))
        XCTAssertNotEqual(generate(seed: 9), generate(seed: 10))
    }

    func testEachSlotGetsADistinctVariationOfItsMovement() {
        let duplicateSlots = [["squat", "squat", "squat"]]
        for workout in generate(days: duplicateSlots) {
            let ids = workout.entries.map(\.exerciseID)
            XCTAssertEqual(Set(ids).count, ids.count)
            XCTAssertEqual(Set(ids), ["back-squat", "goblet-squat", "leg-press"])
            XCTAssertTrue(workout.entries.allSatisfy { $0.sets.count >= 3 && $0.sets.count <= 4 })
        }
    }

    func testHiddenExercisesNeverAppearAndExhaustedSlotsUseSubstitutes() {
        let selector = Fixture.selector { $0.update("barbell-curl") { $0.isHidden = true } }
        let entries = generate(days: [["curl", "press"]], selector: selector).flatMap(\.entries)
        XCTAssertFalse(entries.contains { $0.exerciseID == "barbell-curl" })
        XCTAssertFalse(entries.contains { $0.movementType == "curl" }, "curl has no other variation or same-muscle substitute")

        let squatsHidden = Fixture.selector { exercises in
            for id in ["back-squat", "goblet-squat", "leg-press"] { exercises.update(id) { $0.isHidden = true } }
        }
        let substitutes = generate(days: [["squat"]], selector: squatsHidden).flatMap(\.entries)
        XCTAssertTrue(substitutes.allSatisfy { $0.isSubstitute && ["split-squat", "walking-lunge"].contains($0.exerciseID) })
    }

    func testLikedExercisesShowUpMoreOften() {
        func share(of id: String, _ selector: VariationSelector) -> Double {
            let entries = generate(days: [["squat"]], selector: selector).flatMap(\.entries)
            return Double(entries.filter { $0.exerciseID == id }.count) / Double(entries.count)
        }
        let liked = Fixture.selector { $0.update("leg-press") { $0.isLiked = true } }
        XCTAssertGreaterThan(share(of: "leg-press", liked), share(of: "leg-press", Fixture.selector()))
        XCTAssertGreaterThan(share(of: "leg-press", liked), 0.4)
    }

    func testWeightsProgressAndBodyweightStaysAtZero() {
        let entries = generate(days: [["squat", "press"]]).flatMap(\.entries)
        let squats = entries.filter { $0.exerciseID == "back-squat" }.compactMap { $0.sets.first?.values.weightLb }
        XCTAssertGreaterThan(squats.count, 10)
        XCTAssertEqual(squats.first, 135)
        XCTAssertGreaterThan(squats.last!, squats.first!)
        XCTAssertTrue(squats.allSatisfy { $0.truncatingRemainder(dividingBy: 5) == 0 })

        let pushUps = entries.filter { $0.exerciseID == "push-up" }.flatMap(\.sets)
        XCTAssertFalse(pushUps.isEmpty)
        XCTAssertTrue(pushUps.allSatisfy { $0.values.weightLb == 0 })
    }

    func testNothingToGenerateFromEmptyDays() {
        XCTAssertTrue(generate(days: []).isEmpty)
        XCTAssertTrue(generate(days: [[], []]).isEmpty)
        XCTAssertTrue(generate(weeks: 0).isEmpty)
        XCTAssertEqual(generate(days: [[], ["press"]]).first?.dayIndex, 1, "day indexes still point at the input")
    }
}
