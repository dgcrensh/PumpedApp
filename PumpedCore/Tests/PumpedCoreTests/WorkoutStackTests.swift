import XCTest
@testable import PumpedCore

final class WorkoutStackTests: XCTestCase {
    private var selector = Fixture.selector()
    private var rng = SeededGenerator(seed: 11)

    private func lifting(_ slots: [String]) -> WorkoutStack {
        var stack = WorkoutStack.build(slots: slots, selector: selector, using: &rng)
        stack.startLifting()
        return stack
    }

    // MARK: Building

    func testBuildFillsSlotsInOrderAndStartsInWarmup() {
        let stack = WorkoutStack.build(slots: ["squat", "press", "curl"], selector: selector, using: &rng)
        XCTAssertEqual(stack.phase, .warmup)
        XCTAssertNil(stack.current)
        XCTAssertEqual(stack.pending.map(\.movementType), ["squat", "press", "curl"])
        XCTAssertEqual(stack.pending.map(\.id), [0, 1, 2])
        XCTAssertEqual(stack.entry(2)?.fill, .variation(exerciseID: "barbell-curl"))
    }

    func testDuplicateSlotsGetDistinctVariations() {
        let stack = WorkoutStack.build(slots: ["squat", "squat", "squat"], selector: selector, using: &rng)
        let ids = stack.entries.compactMap(\.exerciseID)
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertTrue(stack.entries.allSatisfy { !$0.fill.isSubstitute })
    }

    func testDuplicateSlotsBeyondVariationsFallBackThenRunOut() {
        // 3 squat variations, then 2 same-muscle lunges, then nothing.
        let stack = WorkoutStack.build(slots: Array(repeating: "squat", count: 6), selector: selector, using: &rng)
        let fills = stack.entries.map(\.fill)
        XCTAssertEqual(fills.prefix(3).filter { !$0.isSubstitute && $0.exerciseID != nil }.count, 3)
        XCTAssertEqual(fills[3...4].filter(\.isSubstitute).count, 2)
        XCTAssertEqual(fills[5], .unavailable)
        XCTAssertEqual(Set(fills.compactMap(\.exerciseID)).count, 5)
    }

    func testSameSeedBuildsTheSameStack() {
        var a = SeededGenerator(seed: 5), b = SeededGenerator(seed: 5)
        let slots = ["squat", "press", "squat", "lunge", "press"]
        XCTAssertEqual(
            WorkoutStack.build(slots: slots, selector: selector, using: &a),
            WorkoutStack.build(slots: slots, selector: selector, using: &b)
        )
    }

    // MARK: Phases

    func testPhaseTransitions() {
        var stack = WorkoutStack.build(slots: ["squat"], selector: selector, using: &rng)
        XCTAssertFalse(stack.finishLifting())
        XCTAssertFalse(stack.finishCooldown())
        XCTAssertTrue(stack.startLifting())
        XCTAssertEqual(stack.phase, .lifting)
        XCTAssertFalse(stack.startLifting())
        XCTAssertTrue(stack.finishLifting())
        XCTAssertEqual(stack.phase, .cooldown)
        XCTAssertNil(stack.current)
        XCTAssertNil(stack.swipeRight())
        XCTAssertTrue(stack.finishCooldown())
        XCTAssertEqual(stack.phase, .complete)
    }

    func testEmptyStackSkipsLifting() {
        var stack = WorkoutStack.build(slots: [], selector: selector, using: &rng)
        stack.startLifting()
        XCTAssertEqual(stack.phase, .cooldown)
    }

    func testFinishLiftingEarlyLeavesCardsPending() {
        var stack = lifting(["squat", "press"])
        stack.swipeRight()
        stack.finishLifting()
        XCTAssertEqual(stack.pending.map(\.movementType), ["press"])
        XCTAssertEqual(stack.entries.map(\.status), [.done, .pending])
    }

    // MARK: Swipes

    func testSwipeRightFinishesTheCardAndAutoAdvancesToCooldown() {
        var stack = lifting(["squat", "press"])
        XCTAssertEqual(stack.swipeRight()?.movementType, "squat")
        XCTAssertEqual(stack.entry(0)?.status, .done)
        XCTAssertEqual(stack.current?.movementType, "press")
        XCTAssertEqual(stack.phase, .lifting)
        stack.swipeRight()
        XCTAssertEqual(stack.phase, .cooldown)
        XCTAssertTrue(stack.pending.isEmpty)
    }

    func testSwipeLeftMovesCardBehindRemainingSlots() {
        var stack = lifting(["squat", "press", "curl"])
        stack.swipeLeft()
        XCTAssertEqual(stack.pending.map(\.movementType), ["press", "curl", "squat"])
        XCTAssertEqual(stack.stackPosition(of: 0), 2)
        // Order is otherwise kept: finishing press leaves curl next, then the deferred squat.
        stack.swipeRight()
        XCTAssertEqual(stack.pending.map(\.movementType), ["curl", "squat"])
    }

    func testSwipeLeftOnTheLastCardKeepsIt() {
        var stack = lifting(["squat"])
        let current = stack.current
        stack.swipeLeft()
        XCTAssertEqual(stack.current, current)
        XCTAssertEqual(stack.phase, .lifting)
    }

    func testSwipeUpLikesAndKeepsTheCard() {
        var stack = lifting(["squat", "press"])
        let current = stack.current!
        XCTAssertEqual(stack.swipeUp(selector: &selector), current.exerciseID)
        XCTAssertEqual(selector.exercise(current.exerciseID!)?.isLiked, true)
        XCTAssertEqual(stack.current, current)
    }

    func testSwipeDownMarksEquipmentAndRefillsWithoutIt() {
        // Leg press and back squat unavailable, so the slot must be goblet squat.
        selector = Fixture.selector(unavailable: ["leg-press", "rack"])
        var stack = lifting(["squat", "press"])
        XCTAssertEqual(stack.current?.exerciseID, "goblet-squat")
        let marked = stack.swipeDown(selector: &selector, using: &rng)
        XCTAssertEqual(marked, ["dumbbells"])
        XCTAssertTrue(selector.unavailableEquipment.contains("dumbbells"))
        // Every squat is gone now; dumbbell split squat is out too, so the substitute is walking lunge.
        XCTAssertEqual(stack.current?.fill, .substitute(exerciseID: "walking-lunge"))
        XCTAssertEqual(stack.current?.id, 0)
        XCTAssertEqual(stack.current?.status, .pending)
    }

    func testSwipeDownRefillNeverRepeatsTheReplacedExercise() {
        var stack = lifting(["lunge"])
        // Swiping the bodyweight lunge marks nothing but still refills.
        while stack.current?.exerciseID != "walking-lunge" {
            stack = lifting(["lunge"])
        }
        let marked = stack.swipeDown(selector: &selector, using: &rng)
        XCTAssertEqual(marked, [])
        XCTAssertNotEqual(stack.current?.exerciseID, "walking-lunge")
        XCTAssertNotNil(stack.current?.exerciseID)
    }

    func testSwipeDownUntilExhaustedShowsNoAvailableVariation() {
        var stack = lifting(["curl"])
        XCTAssertEqual(stack.swipeDown(selector: &selector, using: &rng), ["barbell"])
        XCTAssertEqual(stack.current?.fill, .unavailable)
        // Nothing to mark on an empty card; it can still be swiped away.
        XCTAssertNil(stack.swipeDown(selector: &selector, using: &rng))
        XCTAssertNotNil(stack.swipeRight())
        XCTAssertEqual(stack.phase, .cooldown)
    }

    func testDownSwipedEquipmentAffectsLaterSlots() {
        var stack = lifting(["press", "squat"])
        while stack.current?.exerciseID != "bench-press" { stack = lifting(["press", "squat"]) }
        stack.swipeDown(selector: &selector, using: &rng)
        let added = stack.addSlot("squat", selector: selector, using: &rng)
        XCTAssertNotEqual(added?.exerciseID, "back-squat")
    }

    // MARK: Menu and added slots

    func testHideCurrentRefillsAndHides() {
        var stack = lifting(["curl"])
        XCTAssertEqual(stack.hideCurrent(selector: &selector, using: &rng), "barbell-curl")
        XCTAssertEqual(selector.exercise("barbell-curl")?.isHidden, true)
        XCTAssertEqual(stack.current?.fill, .unavailable)
    }

    func testSwapCurrent() throws {
        var stack = lifting(["squat", "press"])
        let other = stack.entry(1)!.exerciseID!
        XCTAssertFalse(stack.swapCurrent(to: other, selector: selector), "already in the stack")
        XCTAssertFalse(stack.swapCurrent(to: "nope", selector: selector))
        let current = stack.current?.exerciseID
        let squats: [String] = ["back-squat", "goblet-squat", "leg-press"]
        let squat = try XCTUnwrap(squats.first(where: { $0 != current }))
        XCTAssertTrue(stack.swapCurrent(to: squat, selector: selector))
        XCTAssertEqual(stack.current?.fill, .variation(exerciseID: squat))
        XCTAssertTrue(stack.swapCurrent(to: "walking-lunge", selector: selector))
        XCTAssertEqual(stack.current?.fill, .substitute(exerciseID: "walking-lunge"))
    }

    func testSwapOntoAnUnavailableCard() {
        var stack = lifting(["curl", "curl"])
        XCTAssertEqual(stack.swipeLeft()?.fill, .variation(exerciseID: "barbell-curl"))
        XCTAssertEqual(stack.current?.fill, .unavailable)
        XCTAssertTrue(stack.swapCurrent(to: "push-up", selector: selector))
        XCTAssertEqual(stack.current?.fill, .substitute(exerciseID: "push-up"))
    }

    func testAddSlotGoesBehindRemainingCards() {
        var stack = lifting(["squat", "press"])
        stack.swipeLeft()
        let added = stack.addSlot("squat", selector: selector, using: &rng)
        XCTAssertEqual(added?.id, 2)
        XCTAssertEqual(stack.pending.map(\.id), [1, 0, 2])
        XCTAssertNotEqual(added?.exerciseID, stack.entry(0)?.exerciseID)
    }

    func testAddSlotNotAllowedAfterLifting() {
        var stack = lifting(["squat"])
        stack.finishLifting()
        XCTAssertNil(stack.addSlot("press", selector: selector, using: &rng))
    }

    // MARK: Persistence

    func testRoundTripsThroughCodable() throws {
        var stack = lifting(["squat", "press", "curl"])
        stack.swipeLeft()
        stack.swipeRight()
        let data = try JSONEncoder().encode(stack)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutStack.self, from: data), stack)
    }
}
