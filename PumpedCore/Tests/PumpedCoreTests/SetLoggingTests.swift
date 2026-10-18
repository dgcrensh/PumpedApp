import XCTest
@testable import PumpedCore

final class SetLoggingTests: XCTestCase {
    private let last = [SetValues(reps: 8, weightLb: 135), SetValues(reps: 6, weightLb: 145)]

    func testFirstSetRepeatsLastSessionsFirstSet() {
        XCTAssertEqual(SetPrefill.values(today: [], lastSession: last), SetValues(reps: 8, weightLb: 135))
    }

    func testLaterSetsRepeatTodaysLastSet() {
        let today = [SetValues(reps: 8, weightLb: 140), SetValues(reps: 7, weightLb: 140)]
        XCTAssertEqual(SetPrefill.values(today: today, lastSession: last), SetValues(reps: 7, weightLb: 140))
    }

    func testNoHistoryUsesFallback() {
        XCTAssertEqual(SetPrefill.values(today: [], lastSession: []), .fallback)
    }

    func testWeightStepsByFiveAndStopsAtBodyweight() {
        XCTAssertEqual(SetPrefill.stepWeight(135, by: 1), 140)
        XCTAssertEqual(SetPrefill.stepWeight(135, by: -2), 125)
        XCTAssertEqual(SetPrefill.stepWeight(2.5, by: -1), 0)
    }

    func testSummaries() {
        XCTAssertEqual(SetPrefill.summary(last), "8×135, 6×145")
        XCTAssertEqual(SetValues(reps: 10, weightLb: 137.5).summary, "10×137.5")
        XCTAssertEqual(SetValues(reps: 12, weightLb: 0).summary, "12×BW")
        XCTAssertEqual(SetPrefill.summary([]), "")
    }

    func testHistoryFromWorkoutsGroupsByMovementNewestFirst() {
        let history = SelectionHistory(newestFirst: [
            ["squat": ["goblet-squat"], "press": []],
            ["squat": ["back-squat", "front-squat"]],
        ])
        XCTAssertEqual(history.recentWorkouts(of: "squat", limit: 5), [["goblet-squat"], ["back-squat", "front-squat"]])
        XCTAssertTrue(history.recentWorkouts(of: "press", limit: 5).isEmpty)
    }
}
