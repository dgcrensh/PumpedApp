import Foundation
import XCTest
@testable import PumpedCore

final class WorkoutSummaryTests: XCTestCase {
    private func sets(_ pairs: [(Int, Double)]) -> [SetValues] {
        pairs.map { SetValues(reps: $0.0, weightLb: $0.1) }
    }

    func testEpley() {
        XCTAssertEqual(PersonalRecords.estimatedOneRepMax(SetValues(reps: 1, weightLb: 225)), 225)
        XCTAssertEqual(PersonalRecords.estimatedOneRepMax(SetValues(reps: 10, weightLb: 150)), 200, accuracy: 0.0001)
    }

    func testFirstTimeSetsNoPRs() {
        XCTAssertEqual(PersonalRecords.hits(today: sets([(5, 225)]), history: []), [])
    }

    func testHeavierWeightIsAWeightAndOneRepMaxPR() {
        let hits = PersonalRecords.hits(today: sets([(5, 185), (5, 195)]), history: sets([(5, 185)]))
        XCTAssertEqual(hits, [.heaviestWeight(195), .bestEstimatedOneRepMax(195 * (1 + 5.0 / 30))])
    }

    func testHeavierSingleThatDoesNotBeatTheOneRepMax() {
        // 3×195 → 214.5, below 5×185 → 215.8.
        XCTAssertEqual(PersonalRecords.hits(today: sets([(3, 195)]), history: sets([(5, 185)])), [.heaviestWeight(195)])
    }

    func testMoreRepsAtAKnownWeight() {
        let hits = PersonalRecords.hits(today: sets([(10, 135), (9, 135)]), history: sets([(8, 135), (5, 155)]))
        // 10×135 → 180 doesn't beat 5×155 → 180.8, so this is only a reps PR.
        XCTAssertEqual(hits, [.mostReps(10, atWeight: 135)])
    }

    func testNewWeightBelowTheTopIsNotARepsPR() {
        XCTAssertEqual(PersonalRecords.hits(today: sets([(8, 140)]), history: sets([(8, 135), (5, 185)])), [])
    }

    func testMatchingARecordIsNotAPR() {
        XCTAssertEqual(PersonalRecords.hits(today: sets([(5, 185)]), history: sets([(5, 185)])), [])
    }

    func testBodyweightCountsOnlyReps() {
        let hits = PersonalRecords.hits(today: sets([(15, 0)]), history: sets([(12, 0)]))
        XCTAssertEqual(hits, [.mostReps(15, atWeight: 0)])
    }

    func testSummaryTotals() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let summary = WorkoutSummary(
            startedAt: start,
            endedAt: start.addingTimeInterval(65 * 60),
            exercises: [
                .init(name: "Bench Press", sets: sets([(8, 135), (6, 145)]), history: sets([(8, 135)])),
                .init(name: "Skipped", sets: []),
                .init(name: "Push-up", sets: sets([(20, 0)])),
            ]
        )
        XCTAssertEqual(summary.exerciseNames, ["Bench Press", "Push-up"])
        XCTAssertEqual(summary.setCount, 3)
        XCTAssertEqual(summary.volumeLb, 8 * 135 + 6 * 145)
        XCTAssertEqual(summary.prs.map(\.exerciseName), ["Bench Press", "Bench Press"])
        XCTAssertEqual(summary.prs.first?.record, .heaviestWeight(145))
        XCTAssertEqual(WorkoutSummary.durationText(summary.duration), "1 h 5 min")
        XCTAssertEqual(WorkoutSummary.durationText(42 * 60 + 30), "42 min")
        XCTAssertEqual(WorkoutSummary.durationText(20), "under a minute")
    }

    func testPRSummaries() {
        XCTAssertEqual(PersonalRecord.heaviestWeight(185).summary, "Heaviest weight: 185 lb")
        XCTAssertEqual(PersonalRecord.bestEstimatedOneRepMax(215.6).summary, "Best est. 1RM: 216 lb")
        XCTAssertEqual(PersonalRecord.mostReps(10, atWeight: 135).summary, "Most reps at 135 lb: 10")
        XCTAssertEqual(PersonalRecord.mostReps(15, atWeight: 0).summary, "Most reps at bodyweight: 15")
    }
}
