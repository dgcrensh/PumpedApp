import PumpedCore
import SwiftData
import XCTest
@testable import Pumped

@MainActor
final class DebugHistoryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var rng = SeededGenerator(seed: 5)

    override func setUp() async throws {
        container = try PumpedStore.makeContainer(inMemory: true)
        SeedImporter.importBundledSeedIfNeeded(into: context)
    }

    func testGeneratesSixMonthsOverTheActiveSplit() throws {
        let split = SplitEditing.createSplit(named: "Upper/Lower", in: context)
        let upper = SplitEditing.addDay(named: "Upper", to: split, in: context)
        let lower = SplitEditing.addDay(named: "Lower", to: split, in: context)
        SplitEditing.addDay(named: "Empty", to: split, in: context)
        for id in ["horizontal-press", "horizontal-row"] { SplitEditing.addSlot(try movementType(id), to: upper, in: context) }
        for id in ["squat", "hip-hinge"] { SplitEditing.addSlot(try movementType(id), to: lower, in: context) }
        let nextDay = split.nextDayIndex

        let now = Date.now
        let added = DebugHistory.generate(now: now, in: context, using: &rng)
        XCTAssertEqual(added, 26 * 4)

        let sessions = WorkoutFlow.finishedSessions(in: context)
        XCTAssertEqual(sessions.count, added)
        XCTAssertTrue(sessions.allSatisfy { $0.id.hasPrefix(DebugHistory.idPrefix) && $0.phase == .complete })
        XCTAssertEqual(Set(sessions.compactMap { $0.splitDay?.name }), ["Upper", "Lower"], "empty days are skipped")
        XCTAssertTrue(sessions.allSatisfy { $0.split === split && $0.endedAt! <= now })
        XCTAssertGreaterThan(now.timeIntervalSince(sessions.last!.startedAt), 150 * 86_400)
        XCTAssertEqual(split.nextDayIndex, nextDay, "the cycle doesn't move")

        // Generated workouts feed history, PRs and the selector like real ones.
        let entries = sessions.flatMap(\.entries)
        XCTAssertTrue(entries.allSatisfy { $0.exercise != nil && $0.status == .done && $0.sets.count >= 3 })
        let selector = WorkoutFlow.makeSelector(gym: nil, now: now, in: context)
        XCTAssertFalse(selector.history.recentWorkouts(of: "horizontal-press", limit: 5).isEmpty)
    }

    func testFallsBackToPushPullLegsWithoutASplit() {
        XCTAssertGreaterThan(DebugHistory.generate(weeks: 2, in: context, using: &rng), 0)
        let sessions = WorkoutFlow.finishedSessions(in: context)
        XCTAssertTrue(sessions.allSatisfy { $0.split == nil && $0.splitDay == nil && !$0.entries.isEmpty })
    }

    func testRemovingGeneratedHistoryKeepsRealWorkouts() throws {
        let real = WorkoutSession(phase: .complete)
        context.insert(real)
        real.endedAt = .now
        DebugHistory.generate(weeks: 4, in: context, using: &rng)

        XCTAssertEqual(DebugHistory.removeGenerated(in: context), 16)
        XCTAssertEqual(WorkoutFlow.finishedSessions(in: context).map(\.id), [real.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 0)
    }

    private func movementType(_ id: String) throws -> MovementType {
        try XCTUnwrap(context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first)
    }
}
