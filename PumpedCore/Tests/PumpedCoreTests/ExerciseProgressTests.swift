import Foundation
import XCTest
@testable import PumpedCore

final class ExerciseProgressTests: XCTestCase {
    private func sets(_ pairs: [(Int, Double)]) -> [SetValues] {
        pairs.map { SetValues(reps: $0.0, weightLb: $0.1) }
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSinceReferenceDate: Double(n) * 86_400) }

    // MARK: Record book

    func testRecordBookBests() {
        let book = RecordBook(sets: sets([(8, 135), (10, 135), (5, 185), (3, 185), (12, 95)]))
        XCTAssertEqual(book.heaviest, SetValues(reps: 5, weightLb: 185))
        // 5×185 → 215.8 beats 10×135 → 180.
        XCTAssertEqual(book.bestEstimatedOneRepMax, SetValues(reps: 5, weightLb: 185))
        XCTAssertEqual(book.mostReps, sets([(5, 185), (10, 135), (12, 95)]))
    }

    func testRecordBookForBodyweightHasOnlyReps() {
        let book = RecordBook(sets: sets([(12, 0), (15, 0)]))
        XCTAssertNil(book.heaviest)
        XCTAssertNil(book.bestEstimatedOneRepMax)
        XCTAssertEqual(book.mostReps, sets([(15, 0)]))
        XCTAssertTrue(RecordBook(sets: []).isEmpty)
    }

    // MARK: Timeline

    func testTimelineMeasuresEachWorkoutAgainstEarlierOnes() {
        let events = PersonalRecords.timeline([
            DatedSets(date: day(3), sets: sets([(5, 195)])),
            DatedSets(date: day(1), sets: sets([(8, 135)])),
            DatedSets(date: day(2), sets: sets([(10, 135)])),
        ])
        XCTAssertEqual(events, [
            PREvent(date: day(2), record: .bestEstimatedOneRepMax(180)),
            PREvent(date: day(2), record: .mostReps(10, atWeight: 135)),
            PREvent(date: day(3), record: .heaviestWeight(195)),
            PREvent(date: day(3), record: .bestEstimatedOneRepMax(195 * (1 + 5.0 / 30))),
        ])
    }

    func testEditingAnEarlierSetMovesTheRecords() {
        var workouts = [
            DatedSets(date: day(1), sets: sets([(5, 185)])),
            DatedSets(date: day(2), sets: sets([(5, 190)])),
        ]
        XCTAssertEqual(PersonalRecords.timeline(workouts).map(\.record).first, .heaviestWeight(190))

        // The first workout was actually 5×200: day 2 is no longer a PR.
        workouts[0].sets = sets([(5, 200)])
        XCTAssertEqual(PersonalRecords.timeline(workouts), [])
        XCTAssertEqual(RecordBook(sets: workouts.flatMap(\.sets)).heaviest, SetValues(reps: 5, weightLb: 200))

        // Deleting that workout's set makes day 2 the first time again, with nothing to beat.
        workouts[0].sets = []
        XCTAssertEqual(PersonalRecords.timeline(workouts), [])
    }

    // MARK: Per-set check

    func testNewRecordsGoToTheSetThatBreaksThem() {
        let history = sets([(5, 185)])
        XCTAssertEqual(PersonalRecords.newRecords(set: SetValues(reps: 5, weightLb: 185), earlierToday: [], history: history), [])
        XCTAssertEqual(
            PersonalRecords.newRecords(set: SetValues(reps: 5, weightLb: 195), earlierToday: sets([(5, 185)]), history: history),
            [.heaviestWeight(195), .bestEstimatedOneRepMax(195 * (1 + 5.0 / 30))]
        )
        // Repeating today's PR set isn't another PR.
        XCTAssertEqual(
            PersonalRecords.newRecords(set: SetValues(reps: 5, weightLb: 195), earlierToday: sets([(5, 195)]), history: history),
            []
        )
        XCTAssertEqual(PersonalRecords.newRecords(set: SetValues(reps: 6, weightLb: 185), earlierToday: [], history: history),
                       [.bestEstimatedOneRepMax(185 * (1 + 6.0 / 30)), .mostReps(6, atWeight: 185)])
    }

    func testNoRecordsTheFirstTime() {
        XCTAssertEqual(PersonalRecords.newRecords(set: SetValues(reps: 5, weightLb: 135), earlierToday: [], history: []), [])
    }

    // MARK: Chart points

    func testPointsUseTheTopSetAndBestEstimate() {
        let points = ExerciseProgress.points([
            DatedSets(date: day(2), sets: sets([(5, 185), (8, 165), (6, 185)])),
            DatedSets(date: day(1), sets: sets([(10, 135)])),
            DatedSets(date: day(3), sets: []),
        ])
        XCTAssertEqual(points.map(\.date), [day(1), day(2)])
        XCTAssertEqual(points[0].topSet, SetValues(reps: 10, weightLb: 135))
        XCTAssertEqual(points[0].estimatedOneRepMax, 180, accuracy: 0.0001)
        XCTAssertEqual(points[1].topSet, SetValues(reps: 6, weightLb: 185))
        XCTAssertEqual(points[1].topSetWeightLb, 185)
        XCTAssertEqual(points[1].estimatedOneRepMax, 185 * 1.2, accuracy: 0.0001)
    }
}
