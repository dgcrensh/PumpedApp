import Foundation
import XCTest
@testable import PumpedCore

final class ReorderTests: XCTestCase {
    func testMoveDown() {
        // Move "a" below "c": [a b c d] -> [b c a d]
        XCTAssertEqual(Reorder.move(count: 4, fromOffsets: [0], toOffset: 3), [1, 2, 0, 3])
    }

    func testMoveUp() {
        XCTAssertEqual(Reorder.move(count: 4, fromOffsets: [3], toOffset: 1), [0, 3, 1, 2])
    }

    func testMoveToEnd() {
        XCTAssertEqual(Reorder.move(count: 3, fromOffsets: [0], toOffset: 3), [1, 2, 0])
    }

    func testMoveSeveral() {
        XCTAssertEqual(Reorder.move(count: 5, fromOffsets: [0, 2], toOffset: 5), [1, 3, 4, 0, 2])
    }

    func testMoveInPlaceIsIdentity() {
        XCTAssertEqual(Reorder.move(count: 3, fromOffsets: [1], toOffset: 1), [0, 1, 2])
        XCTAssertEqual(Reorder.move(count: 3, fromOffsets: [1], toOffset: 2), [0, 1, 2])
    }

    func testIgnoresOutOfRangeOffsets() {
        XCTAssertEqual(Reorder.move(count: 2, fromOffsets: [5], toOffset: 0), [0, 1])
        XCTAssertEqual(Reorder.move(count: 0, fromOffsets: [0], toOffset: 0), [])
    }
}

final class SplitCycleTests: XCTestCase {
    func testInitWrapsIndex() {
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 4).nextDayIndex, 1)
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: -1).nextDayIndex, 2)
        XCTAssertEqual(SplitCycle(dayCount: 0, nextDayIndex: 5).nextDayIndex, 0)
    }

    func testPosition() {
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 1).position, 2)
        XCTAssertNil(SplitCycle(dayCount: 0, nextDayIndex: 0).position)
    }

    func testAdvanceWraps() {
        let cycle = SplitCycle(dayCount: 3, nextDayIndex: 2)
        XCTAssertEqual(cycle.advanced().nextDayIndex, 0)
        XCTAssertEqual(cycle.advanced().advanced().nextDayIndex, 1)
    }

    func testSetNextDay() {
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 0).settingNextDay(2).nextDayIndex, 2)
    }

    func testInsertingDayBeforeNextKeepsSameDay() {
        let cycle = SplitCycle(dayCount: 3, nextDayIndex: 1)
        XCTAssertEqual(cycle.insertingDay(at: 0), SplitCycle(dayCount: 4, nextDayIndex: 2))
        XCTAssertEqual(cycle.insertingDay(at: 3), SplitCycle(dayCount: 4, nextDayIndex: 1))
        XCTAssertEqual(SplitCycle(dayCount: 0, nextDayIndex: 0).insertingDay(at: 0), SplitCycle(dayCount: 1, nextDayIndex: 0))
    }

    func testRemovingDayBeforeNext() {
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 2).removingDay(at: 0), SplitCycle(dayCount: 2, nextDayIndex: 1))
    }

    func testRemovingNextDayMovesToFollowingDay() {
        // [Push, Pull, Legs], next = Pull. Delete Pull -> Legs is next.
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 1).removingDay(at: 1), SplitCycle(dayCount: 2, nextDayIndex: 1))
        // Deleting the last day while it's next wraps to the first.
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 2).removingDay(at: 2), SplitCycle(dayCount: 2, nextDayIndex: 0))
    }

    func testRemovingDayAfterNext() {
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 0).removingDay(at: 2), SplitCycle(dayCount: 2, nextDayIndex: 0))
    }

    func testRemovingLastDay() {
        XCTAssertEqual(SplitCycle(dayCount: 1, nextDayIndex: 0).removingDay(at: 0), SplitCycle(dayCount: 0, nextDayIndex: 0))
        XCTAssertEqual(SplitCycle(dayCount: 1, nextDayIndex: 0).removingDay(at: 3), SplitCycle(dayCount: 1, nextDayIndex: 0))
    }

    func testRemovingSeveralDays() {
        // [A B C D E], next = D. Delete A and C -> [B D E], D still next.
        XCTAssertEqual(SplitCycle(dayCount: 5, nextDayIndex: 3).removingDays(at: [0, 2]), SplitCycle(dayCount: 3, nextDayIndex: 1))
    }

    func testMovingDaysKeepsSameDayNext() {
        // [Push, Pull, Legs], next = Pull. Move Push to the end -> [Pull, Legs, Push].
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 1).movingDays(fromOffsets: [0], toOffset: 3).nextDayIndex, 0)
        // Move the next day itself.
        XCTAssertEqual(SplitCycle(dayCount: 3, nextDayIndex: 1).movingDays(fromOffsets: [1], toOffset: 0).nextDayIndex, 0)
    }
}
