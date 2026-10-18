import PumpedCore
import SwiftData
import XCTest
@testable import Pumped

@MainActor
final class HistoryDataTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var rng = SeededGenerator(seed: 7)

    override func setUp() async throws {
        container = try PumpedStore.makeContainer(inMemory: true)
        SeedImporter.importBundledSeedIfNeeded(into: context)
    }

    func testWorkoutsAndProgressForAnExercise() throws {
        let first = try workout(daysAgo: 2, exercise: "barbell-bench-press", sets: [(8, 135), (6, 145)])
        let second = try workout(daysAgo: 1, exercise: "barbell-bench-press", sets: [(5, 155)])
        _ = try workout(daysAgo: 0, exercise: "back-squat", sets: [(5, 225)])

        let workouts = HistoryData.workouts(.exercise("barbell-bench-press"), in: context)
        XCTAssertEqual(workouts.map(\.session.id), [second.id, first.id], "newest first")
        XCTAssertEqual(workouts.last?.sets, [SetValues(reps: 8, weightLb: 135), SetValues(reps: 6, weightLb: 145)])

        let points = HistoryData.progress(.exercise("barbell-bench-press"), in: context)
        XCTAssertEqual(points.map(\.topSetWeightLb), [145, 155])
        XCTAssertEqual(HistoryData.records(of: "barbell-bench-press", in: context).heaviest, SetValues(reps: 5, weightLb: 155))
        XCTAssertEqual(HistoryData.trainedExercises(in: context).map(\.id), ["back-squat", "barbell-bench-press"], "by name")
    }

    func testMovementTypeScopeCombinesVariations() throws {
        _ = try workout(daysAgo: 2, exercise: "barbell-bench-press", sets: [(5, 185)])
        _ = try workout(daysAgo: 1, exercise: "dumbbell-bench-press", sets: [(10, 70)])

        XCTAssertEqual(HistoryData.workouts(.exercise("barbell-bench-press"), in: context).count, 1)
        let all = HistoryData.workouts(.movementType("horizontal-press"), in: context)
        XCTAssertEqual(all.map(\.exerciseNames), [["Dumbbell Bench Press"], ["Barbell Bench Press"]])
        XCTAssertEqual(HistoryData.progress(.movementType("horizontal-press"), in: context).count, 2)
    }

    func testEditingAndDeletingSetsRecomputesPRs() throws {
        let first = try workout(daysAgo: 2, exercise: "barbell-bench-press", sets: [(5, 185)])
        let second = try workout(daysAgo: 1, exercise: "barbell-bench-press", sets: [(5, 190)])
        XCTAssertEqual(HistoryData.prs(in: second, context: context).first?.record, .heaviestWeight(190))

        // The first workout was really 5×200, so the second one set no PR.
        let firstSet = try XCTUnwrap(first.entries.first?.sets.first)
        HistoryData.update(firstSet, to: SetValues(reps: 5, weightLb: 200), in: context)
        XCTAssertEqual(HistoryData.prs(in: second, context: context), [])
        XCTAssertEqual(HistoryData.records(of: "barbell-bench-press", in: context).heaviest, SetValues(reps: 5, weightLb: 200))
        XCTAssertEqual(HistoryData.prTimeline(of: "barbell-bench-press", in: context), [])

        // With that set gone, the second workout is the first time again: nothing to beat.
        HistoryData.delete(firstSet, in: context)
        XCTAssertEqual(HistoryData.workouts(.exercise("barbell-bench-press"), in: context).count, 1)
        XCTAssertEqual(HistoryData.prs(in: second, context: context), [])
        XCTAssertEqual(HistoryData.records(of: "barbell-bench-press", in: context).heaviest, SetValues(reps: 5, weightLb: 190))
    }

    func testUpdateClampsRepsAndWeight() throws {
        let session = try workout(daysAgo: 1, exercise: "push-up", sets: [(12, 0)])
        let set = try XCTUnwrap(session.entries.first?.sets.first)
        HistoryData.update(set, to: SetValues(reps: 0, weightLb: -5), in: context)
        XCTAssertEqual(set.reps, 1)
        XCTAssertEqual(set.weightLb, 0)
    }

    func testDeletingAWorkoutRemovesItsSets() throws {
        let session = try workout(daysAgo: 1, exercise: "barbell-bench-press", sets: [(5, 185), (5, 185)])
        HistoryData.delete(session, in: context)
        XCTAssertTrue(WorkoutFlow.finishedSessions(in: context).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 0)
        XCTAssertTrue(HistoryData.trainedExercises(in: context).isEmpty)
    }

    func testSampleHistoryChartsTwelveWorkouts() throws {
        UITestingData.addSampleHistory(to: context)
        let points = HistoryData.progress(.exercise("barbell-bench-press"), in: context)
        XCTAssertEqual(points.count, 12)
        XCTAssertEqual(points.last?.topSetWeightLb, 190)
        let newest = try XCTUnwrap(WorkoutFlow.finishedSessions(in: context).first)
        XCTAssertEqual(HistoryData.prs(in: newest, context: context).first?.record, .heaviestWeight(190))
    }

    // MARK: Helpers

    /// A finished workout of one card with `exercise` swapped in and `sets` logged.
    private func workout(daysAgo: Int, exercise: String, sets: [(Int, Double)]) throws -> WorkoutSession {
        let split = SplitEditing.createSplit(named: "Full", in: context)
        let day = SplitEditing.addDay(named: "Day", to: split, in: context)
        let movementType = try XCTUnwrap(fetchExercise(exercise).movementType)
        SplitEditing.addSlot(movementType, to: day, in: context)

        let start = Date.now.addingTimeInterval(-Double(daysAgo) * 86_400 - 3_600)
        let session = WorkoutFlow.start(day: day, of: split, gym: nil, at: start, in: context, using: &rng)
        WorkoutFlow.skipWarmup(session, in: context)
        XCTAssertEqual(WorkoutFlow.swapCurrent(to: exercise, in: session, context: context), .applied)
        let card = try XCTUnwrap(WorkoutFlow.currentEntry(of: session))
        for (index, set) in sets.enumerated() {
            WorkoutFlow.logSet(SetValues(reps: set.0, weightLb: set.1), on: card, at: start.addingTimeInterval(Double(index + 1) * 60), in: context)
        }
        WorkoutFlow.finish(session, cooldownCompleted: true, at: start.addingTimeInterval(1_800), in: context)
        return session
    }

    private func fetchExercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first)
    }
}
