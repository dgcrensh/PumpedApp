import Foundation
import XCTest
@testable import PumpedCore

final class RestTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testStartCountsDownFromAnAbsoluteEnd() {
        var timer = RestTimer()
        XCTAssertFalse(timer.isRunning(at: t0))
        timer.start(seconds: 120, at: t0)
        XCTAssertEqual(timer.endsAt, t0.addingTimeInterval(120))
        XCTAssertEqual(timer.displaySeconds(at: t0.addingTimeInterval(30.4)), 90)
        XCTAssertTrue(timer.isRunning(at: t0.addingTimeInterval(119.5)))
        XCTAssertFalse(timer.isRunning(at: t0.addingTimeInterval(120)))
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(500)), 0, "never negative, e.g. after a long background")
    }

    func testLoggingAnotherSetRestartsTheRest() {
        var timer = RestTimer()
        timer.start(seconds: 180, at: t0)
        timer.start(seconds: 60, at: t0.addingTimeInterval(20))
        XCTAssertEqual(timer.endsAt, t0.addingTimeInterval(80))
    }

    func testSkipStops() {
        var timer = RestTimer(endsAt: t0.addingTimeInterval(60))
        timer.skip()
        XCTAssertNil(timer.endsAt)
        XCTAssertFalse(timer.isRunning(at: t0))
    }

    func testExtendAddsThirtySecondsOrRestartsWhenOver() {
        var timer = RestTimer()
        timer.start(seconds: 60, at: t0)
        timer.extend(at: t0.addingTimeInterval(10))
        XCTAssertEqual(timer.endsAt, t0.addingTimeInterval(90))

        timer.extend(at: t0.addingTimeInterval(200))
        XCTAssertEqual(timer.endsAt, t0.addingTimeInterval(230))
    }

    func testZeroSecondsStartsNothing() {
        var timer = RestTimer(endsAt: t0)
        timer.start(seconds: 0, at: t0)
        XCTAssertNil(timer.endsAt)
    }

    func testDefaultRestPerExerciseType() {
        XCTAssertEqual(ExerciseType.allCases.map(\.defaultRestSeconds), [180, 120, 60])
    }

    func testCountdownText() {
        XCTAssertEqual(CountdownText.format(0), "0:00")
        XCTAssertEqual(CountdownText.format(65), "1:05")
        XCTAssertEqual(CountdownText.format(180), "3:00")
        XCTAssertEqual(CountdownText.format(3_725), "1:02:05")
        XCTAssertEqual(CountdownText.format(-4), "0:00")
    }
}
