import PumpedCore
import SwiftData
import XCTest
@testable import Pumped

@MainActor
final class WorkoutFlowTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var rng = SeededGenerator(seed: 42)

    override func setUp() async throws {
        container = try PumpedStore.makeContainer(inMemory: true)
        SeedImporter.importBundledSeedIfNeeded(into: context)
    }

    // MARK: Starting

    func testStartFillsEverySlotInOrderWithDistinctExercises() throws {
        let (split, push) = try pushPull(pushSlots: ["horizontal-press", "horizontal-press", "triceps-extension"])
        let session = WorkoutFlow.start(day: push, of: split, gym: nil, in: context, using: &rng)

        XCTAssertEqual(session.phase, .warmup)
        XCTAssertTrue(WorkoutFlow.activeSession(in: context) === session)
        let entries = session.entries.sorted { $0.slotOrder < $1.slotOrder }
        XCTAssertEqual(entries.map(\.movementTypeID), ["horizontal-press", "horizontal-press", "triceps-extension"])
        XCTAssertEqual(entries.map(\.stackPosition), [0, 1, 2])
        XCTAssertEqual(Set(entries.compactMap { $0.exercise?.id }).count, 3)
        XCTAssertNil(WorkoutFlow.currentEntry(of: session), "no card on top during the warmup")
    }

    func testWarmupLogStartsLifting() throws {
        let session = try startedSession()
        let rower = try XCTUnwrap(context.fetch(FetchDescriptor<CardioOption>()).first)
        WorkoutFlow.logWarmup(cardio: rower, durationSec: 600, distanceMi: 1.2, in: session, context: context)

        XCTAssertEqual(session.phase, .lifting)
        XCTAssertEqual(session.warmup?.durationSec, 600)
        XCTAssertEqual(session.warmup?.distanceMi, 1.2)
        XCTAssertEqual(WorkoutFlow.currentEntry(of: session)?.slotOrder, 0)
    }

    // MARK: Swipes

    func testRightAndLeftSwipesReorderAndUndo() throws {
        let session = try liftingSession(slots: ["horizontal-press", "chest-fly", "triceps-extension"])

        let left = WorkoutFlow.swipe(.left, in: session, context: context, using: &rng)
        XCTAssertEqual(left.result, .applied)
        XCTAssertEqual(WorkoutFlow.stack(of: session).pending.map(\.id), [1, 2, 0])

        let right = WorkoutFlow.swipe(.right, in: session, context: context, using: &rng)
        XCTAssertEqual(WorkoutFlow.stack(of: session).pending.map(\.id), [2, 0])
        XCTAssertEqual(entry(1, of: session)?.status, .done)
        XCTAssertEqual(entry(1, of: session)?.stackPosition, -1)

        WorkoutFlow.undo(try XCTUnwrap(right.undo), in: session, context: context)
        XCTAssertEqual(WorkoutFlow.stack(of: session).pending.map(\.id), [1, 2, 0])
        XCTAssertEqual(entry(1, of: session)?.status, .pending)
    }

    func testLastRightSwipeMovesToCooldownAndUndoComesBack() throws {
        let session = try liftingSession(slots: ["horizontal-press"])
        let right = WorkoutFlow.swipe(.right, in: session, context: context, using: &rng)
        XCTAssertEqual(session.phase, .cooldown)

        WorkoutFlow.undo(try XCTUnwrap(right.undo), in: session, context: context)
        XCTAssertEqual(session.phase, .lifting)
        XCTAssertEqual(WorkoutFlow.currentEntry(of: session)?.slotOrder, 0)
    }

    func testUpSwipeLikesAndUndoUnlikes() throws {
        let session = try liftingSession(slots: ["horizontal-press"])
        let exercise = try XCTUnwrap(WorkoutFlow.currentEntry(of: session)?.exercise)
        XCTAssertFalse(exercise.isLiked)

        let up = WorkoutFlow.swipe(.up, in: session, context: context, using: &rng)
        XCTAssertTrue(exercise.isLiked)
        XCTAssertTrue(WorkoutFlow.currentEntry(of: session)?.exercise === exercise, "the card stays")

        WorkoutFlow.undo(try XCTUnwrap(up.undo), in: session, context: context)
        XCTAssertFalse(exercise.isLiked)
    }

    func testDownSwipeRefillsAndMarksEquipmentAtTheGym() throws {
        let gym = Gym(name: "Home gym", latitude: 0, longitude: 0)
        context.insert(gym)
        let session = try liftingSession(slots: ["horizontal-press"], gym: gym)
        let barbell = try exerciseWithEquipment(movementType: "horizontal-press")
        XCTAssertEqual(WorkoutFlow.swapCurrent(to: barbell.id, in: session, context: context), .applied)

        let down = WorkoutFlow.swipe(.down, in: session, context: context, using: &rng)
        XCTAssertEqual(down.result, .applied)
        XCTAssertNil(down.undo)

        let refill = try XCTUnwrap(WorkoutFlow.currentEntry(of: session)?.exercise)
        XCTAssertNotEqual(refill.id, barbell.id)
        let marked = Set(gym.unavailableEquipment.compactMap { $0.equipment?.id })
        XCTAssertEqual(marked, Set(barbell.equipment.map(\.id)))
        XCTAssertTrue(Set(refill.equipment.map(\.id)).isDisjoint(with: marked))
    }

    func testCardsWithSetsKeepTheirExercise() throws {
        let session = try liftingSession(slots: ["horizontal-press"])
        let current = try XCTUnwrap(WorkoutFlow.currentEntry(of: session))
        let exercise = current.exercise
        WorkoutFlow.logSet(SetValues(reps: 8, weightLb: 135), on: current, in: context)

        XCTAssertEqual(WorkoutFlow.swipe(.down, in: session, context: context, using: &rng).result, .hasSets)
        XCTAssertEqual(WorkoutFlow.hideCurrent(in: session, context: context, using: &rng), .hasSets)
        XCTAssertTrue(current.exercise === exercise)
        XCTAssertEqual(exercise?.isHidden, false)
    }

    // MARK: Card menu and extra slots

    func testHideCurrentHidesAndRefills() throws {
        let session = try liftingSession(slots: ["horizontal-press"])
        let hidden = try XCTUnwrap(WorkoutFlow.currentEntry(of: session)?.exercise)
        XCTAssertEqual(WorkoutFlow.hideCurrent(in: session, context: context, using: &rng), .applied)
        XCTAssertTrue(hidden.isHidden)
        XCTAssertFalse(WorkoutFlow.currentEntry(of: session)?.exercise === hidden)
    }

    func testAddExerciseGoesBehindTheRemainingCards() throws {
        let session = try liftingSession(slots: ["horizontal-press", "chest-fly"])
        XCTAssertTrue(WorkoutFlow.addExercise(movementTypeID: "lateral-raise", to: session, context: context, using: &rng))
        let added = try XCTUnwrap(entry(2, of: session))
        XCTAssertEqual(added.movementTypeID, "lateral-raise")
        XCTAssertEqual(WorkoutFlow.stack(of: session).pending.map(\.id), [0, 1, 2])
    }

    // MARK: Resume

    func testWorkoutSurvivesRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let expectedStack: WorkoutStack
        let exerciseID: String?
        do {
            container = try PumpedStore.makeContainer(url: url)
            SeedImporter.importBundledSeedIfNeeded(into: context)
            let session = try liftingSession(slots: ["horizontal-press", "chest-fly", "triceps-extension"])
            let current = try XCTUnwrap(WorkoutFlow.currentEntry(of: session))
            exerciseID = current.exercise?.id
            WorkoutFlow.logSet(SetValues(reps: 8, weightLb: 135), on: current, in: context)
            WorkoutFlow.logSet(SetValues(reps: 6, weightLb: 140), on: current, in: context)
            _ = WorkoutFlow.swipe(.left, in: session, context: context, using: &rng)
            expectedStack = WorkoutFlow.stack(of: session)
        }

        // A fresh container on the same file, as after a force-quit.
        container = nil
        container = try PumpedStore.makeContainer(url: url)
        let resumed = try XCTUnwrap(WorkoutFlow.activeSession(in: context))
        XCTAssertEqual(WorkoutFlow.stack(of: resumed), expectedStack)
        XCTAssertEqual(resumed.phase, .lifting)
        let pressCard = try XCTUnwrap(resumed.entries.first { $0.slotOrder == 0 })
        XCTAssertEqual(pressCard.exercise?.id, exerciseID)
        XCTAssertEqual(pressCard.orderedSets.map(WorkoutFlow.values), [
            SetValues(reps: 8, weightLb: 135),
            SetValues(reps: 6, weightLb: 140),
        ])
    }

    // MARK: Finishing and history

    func testFinishAdvancesTheSplitOnlyWhenSetsWereLogged() throws {
        let (split, push) = try pushPull(pushSlots: ["horizontal-press"])

        let empty = WorkoutFlow.start(day: push, of: split, gym: nil, in: context, using: &rng)
        WorkoutFlow.finish(empty, cooldownCompleted: false, in: context)
        XCTAssertNotNil(empty.endedAt)
        XCTAssertEqual(empty.phase, .complete)
        XCTAssertEqual(SplitEditing.nextDay(of: split)?.name, "Push")
        XCTAssertNil(WorkoutFlow.activeSession(in: context))

        let real = WorkoutFlow.start(day: push, of: split, gym: nil, in: context, using: &rng)
        WorkoutFlow.skipWarmup(real, in: context)
        WorkoutFlow.logSet(SetValues(reps: 5, weightLb: 185), on: try XCTUnwrap(WorkoutFlow.currentEntry(of: real)), in: context)
        WorkoutFlow.finish(real, cooldownCompleted: true, in: context)
        XCTAssertTrue(real.cooldownCompleted)
        XCTAssertEqual(SplitEditing.nextDay(of: split)?.name, "Pull")
    }

    func testDiscardDeletesTheWorkoutAndKeepsTheSplit() throws {
        let (split, push) = try pushPull(pushSlots: ["horizontal-press"])
        let session = WorkoutFlow.start(day: push, of: split, gym: nil, in: context, using: &rng)
        WorkoutFlow.discard(session, in: context)
        XCTAssertNil(WorkoutFlow.activeSession(in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutEntry>()), 0)
        XCTAssertEqual(SplitEditing.nextDay(of: split)?.name, "Push")
    }

    func testLastSetsAndHistoryComeFromFinishedWorkouts() throws {
        let (split, push) = try pushPull(pushSlots: ["horizontal-press"])
        let first = WorkoutFlow.start(day: push, of: split, gym: nil, at: .now.addingTimeInterval(-86_400), in: context, using: &rng)
        WorkoutFlow.skipWarmup(first, in: context)
        let card = try XCTUnwrap(WorkoutFlow.currentEntry(of: first))
        let exerciseID = try XCTUnwrap(card.exercise?.id)
        WorkoutFlow.logSet(SetValues(reps: 8, weightLb: 135), on: card, in: context)
        WorkoutFlow.logSet(SetValues(reps: 6, weightLb: 135), on: card, in: context)
        WorkoutFlow.finish(first, cooldownCompleted: true, in: context)

        let second = WorkoutFlow.start(day: push, of: split, gym: nil, in: context, using: &rng)
        let last = try XCTUnwrap(WorkoutFlow.lastSets(of: exerciseID, before: second, in: context))
        XCTAssertEqual(last.sets, [SetValues(reps: 8, weightLb: 135), SetValues(reps: 6, weightLb: 135)])
        XCTAssertNil(WorkoutFlow.lastSets(of: exerciseID, before: first, in: context))

        let history = WorkoutFlow.history(excluding: second, in: context)
        XCTAssertEqual(history.recentWorkouts(of: "horizontal-press", limit: 5), [[exerciseID]])
    }

    // MARK: Helpers

    private func pushPull(pushSlots: [String]) throws -> (Split, SplitDay) {
        let split = SplitEditing.createSplit(named: "PPL", in: context)
        let push = SplitEditing.addDay(named: "Push", to: split, in: context)
        SplitEditing.addDay(named: "Pull", to: split, in: context)
        for id in pushSlots {
            let movementType = try XCTUnwrap(context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first)
            SplitEditing.addSlot(movementType, to: push, in: context)
        }
        return (split, push)
    }

    private func startedSession(slots: [String] = ["horizontal-press"], gym: Gym? = nil) throws -> WorkoutSession {
        let (split, push) = try pushPull(pushSlots: slots)
        return WorkoutFlow.start(day: push, of: split, gym: gym, in: context, using: &rng)
    }

    private func liftingSession(slots: [String], gym: Gym? = nil) throws -> WorkoutSession {
        let session = try startedSession(slots: slots, gym: gym)
        WorkoutFlow.skipWarmup(session, in: context)
        return session
    }

    private func entry(_ slotOrder: Int, of session: WorkoutSession) -> WorkoutEntry? {
        session.entries.first { $0.slotOrder == slotOrder }
    }

    private func exerciseWithEquipment(movementType: String) throws -> Exercise {
        let all = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.id)]))
        return try XCTUnwrap(all.first { $0.movementType?.id == movementType && !$0.equipment.isEmpty })
    }
}
