import Foundation
import XCTest
@testable import PumpedCore

final class CooldownPlayerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func testStartsRunningOnTheFirstStretch() {
        let player = CooldownPlayer(durations: [30, 45, 60], at: t0)
        XCTAssertEqual(player.index, 0)
        XCTAssertFalse(player.isPaused)
        XCTAssertEqual(player.displaySeconds(at: at(10)), 20)
    }

    func testAutoAdvancesWhenTimeRunsOut() {
        var player = CooldownPlayer(durations: [30, 45, 60], at: t0)
        XCTAssertEqual(player.update(at: at(29)), 0)
        XCTAssertEqual(player.update(at: at(30)), 1)
        XCTAssertEqual(player.index, 1)
        XCTAssertEqual(player.displaySeconds(at: at(30)), 45)
    }

    func testCatchesUpAfterTheBackground() {
        var player = CooldownPlayer(durations: [30, 45, 60], at: t0)
        XCTAssertEqual(player.update(at: at(100)), 2, "30 + 45 elapsed, 25 s into the third")
        XCTAssertEqual(player.index, 2)
        XCTAssertEqual(player.displaySeconds(at: at(100)), 35)

        XCTAssertEqual(player.update(at: at(1_000)), 1)
        XCTAssertTrue(player.isFinished)
        XCTAssertEqual(player.remaining(at: at(1_000)), 0)
        XCTAssertEqual(player.update(at: at(2_000)), 0)
    }

    func testPauseHoldsTheTimeAndResumeContinues() {
        var player = CooldownPlayer(durations: [30, 45], at: t0)
        player.pause(at: at(10))
        XCTAssertTrue(player.isPaused)
        XCTAssertEqual(player.update(at: at(500)), 0, "nothing moves while paused")
        XCTAssertEqual(player.displaySeconds(at: at(500)), 20)

        player.resume(at: at(500))
        XCTAssertFalse(player.isPaused)
        XCTAssertEqual(player.displaySeconds(at: at(505)), 15)
        XCTAssertEqual(player.update(at: at(520)), 1)
        XCTAssertEqual(player.index, 1)
    }

    func testSkipStartsTheNextStretchWithItsFullTime() {
        var player = CooldownPlayer(durations: [30, 45], at: t0)
        player.skip(at: at(5))
        XCTAssertEqual(player.index, 1)
        XCTAssertEqual(player.displaySeconds(at: at(5)), 45)

        player.skip(at: at(6))
        XCTAssertTrue(player.isFinished)
        player.skip(at: at(7))
        XCTAssertEqual(player.index, 2, "skipping past the end stays finished")
    }

    func testBackGoesToThePreviousStretchOrRestartsTheFirst() {
        var player = CooldownPlayer(durations: [30, 45], at: t0)
        player.back(at: at(10))
        XCTAssertEqual(player.index, 0)
        XCTAssertEqual(player.displaySeconds(at: at(10)), 30)

        player.skip(at: at(12))
        player.back(at: at(15))
        XCTAssertEqual(player.index, 0)
        XCTAssertEqual(player.displaySeconds(at: at(15)), 30)
    }

    func testBackFromTheEndReopensTheLastStretch() {
        var player = CooldownPlayer(durations: [30, 45], at: t0)
        player.update(at: at(200))
        XCTAssertTrue(player.isFinished)
        player.back(at: at(200))
        XCTAssertEqual(player.index, 1)
        XCTAssertEqual(player.displaySeconds(at: at(200)), 45)
    }

    func testSkipAndBackKeepAPausedPlayerPaused() {
        var player = CooldownPlayer(durations: [30, 45, 60], at: t0)
        player.pause(at: at(10))
        player.skip(at: at(20))
        XCTAssertTrue(player.isPaused)
        XCTAssertEqual(player.displaySeconds(at: at(300)), 45)
        player.back(at: at(300))
        XCTAssertTrue(player.isPaused)
        XCTAssertEqual(player.index, 0)
        XCTAssertEqual(player.displaySeconds(at: at(300)), 30)
    }

    func testEmptySequenceIsFinished() {
        var player = CooldownPlayer(durations: [], at: t0)
        XCTAssertTrue(player.isFinished)
        player.back(at: t0)
        player.skip(at: t0)
        XCTAssertTrue(player.isFinished)
    }

    func testRoundTripsThroughCodable() throws {
        var player = CooldownPlayer(durations: [30, 45], at: t0)
        player.pause(at: at(12))
        let decoded = try JSONDecoder().decode(CooldownPlayer.self, from: JSONEncoder().encode(player))
        XCTAssertEqual(decoded, player)
    }
}
