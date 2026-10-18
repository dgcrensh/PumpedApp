import PumpedCore
import SwiftData
import XCTest
@testable import Pumped

@MainActor
final class GymEditingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var rng = SeededGenerator(seed: 7)
    private let downtown = Coordinate(latitude: 39.7392, longitude: -104.9903)
    private let boulder = Coordinate(latitude: 40.0150, longitude: -105.2705)

    override func setUp() async throws {
        container = try PumpedStore.makeContainer(inMemory: true)
        SeedImporter.importBundledSeedIfNeeded(into: context)
    }

    // MARK: Detection

    func testDetectionMatchesSavedGymsAndOffersNewOnes() {
        let gym = GymEditing.createGym(named: "Downtown", at: downtown, in: context)
        XCTAssertEqual(GymEditing.detect(.located(downtown), in: context), .matched(gymID: gym.id))
        XCTAssertEqual(GymEditing.detect(.located(boulder), in: context), .newGym(boulder))
        XCTAssertEqual(GymEditing.detect(.denied, in: context), .pickGym)
    }

    func testNoLocationAndNoGymsStartsWithNoGym() {
        XCTAssertEqual(GymEditing.detect(.denied, in: context), .noGym)
        XCTAssertEqual(GymEditing.detect(.unavailable, in: context), .noGym)
    }

    // MARK: Editing

    func testCreateAndRename() {
        let gym = GymEditing.createGym(named: "  Downtown  ", at: downtown, in: context)
        XCTAssertEqual(gym.name, "Downtown")
        XCTAssertEqual(gym.latitude, downtown.latitude)
        XCTAssertEqual(gym.radius, GymMatcher.defaultRadius)

        GymEditing.rename(gym, to: "Downtown Y", in: context)
        XCTAssertEqual(gym.name, "Downtown Y")
        GymEditing.rename(gym, to: "   ", in: context)
        XCTAssertEqual(gym.name, "Downtown Y", "a blank name keeps the old one")
        XCTAssertEqual(GymEditing.createGym(named: "", at: boulder, in: context).name, GymEditing.defaultName)
    }

    func testDeleteKeepsWorkoutsAndDropsTheGymsEquipment() throws {
        let gym = GymEditing.createGym(named: "Downtown", at: downtown, in: context)
        let session = try liftingSession(at: gym)
        try swipeDownOnEquipment(in: session)
        XCTAssertFalse(gym.unavailableEquipment.isEmpty)

        GymEditing.delete(gym, in: context)
        XCTAssertNil(session.gym)
        XCTAssertTrue(GymEditing.allGyms(in: context).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EquipmentUnavailability>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

    func testChangingTheGymMidWorkout() throws {
        let a = GymEditing.createGym(named: "A", at: downtown, in: context)
        let b = GymEditing.createGym(named: "B", at: boulder, in: context)
        let session = try liftingSession(at: a)
        GymEditing.changeGym(of: session, to: b, in: context)
        XCTAssertTrue(session.gym === b)
        GymEditing.changeGym(of: session, to: nil, in: context)
        XCTAssertNil(session.gym)
    }

    // MARK: Unavailable equipment

    /// M7 acceptance: two gyms with different unavailable equipment behave independently.
    func testTwoGymsRememberDifferentEquipment() throws {
        let a = GymEditing.createGym(named: "A", at: downtown, in: context)
        let b = GymEditing.createGym(named: "B", at: boulder, in: context)

        let atA = try liftingSession(at: a)
        let markedAtA = try swipeDownOnEquipment(in: atA)
        WorkoutFlow.finish(atA, cooldownCompleted: false, in: context)

        let atB = try liftingSession(at: b)
        let markedAtB = try swipeDownOnEquipment(in: atB, avoiding: markedAtA)
        WorkoutFlow.finish(atB, cooldownCompleted: false, in: context)

        XCTAssertTrue(markedAtA.isDisjoint(with: markedAtB))
        XCTAssertEqual(WorkoutFlow.unavailableEquipment(at: a, now: .now), markedAtA)
        XCTAssertEqual(WorkoutFlow.unavailableEquipment(at: b, now: .now), markedAtB)
        XCTAssertEqual(WorkoutFlow.unavailableEquipment(at: nil, now: .now), [])

        // A new workout at B can still pick A's unavailable equipment, and not B's.
        let selector = WorkoutFlow.makeSelector(gym: b, now: .now, in: context)
        XCTAssertEqual(selector.unavailableEquipment, markedAtB)
    }

    func testNoGymDownSwipeOnlyRefills() throws {
        let session = try liftingSession(at: nil)
        try swipeDownOnEquipment(in: session)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EquipmentUnavailability>()), 0)
        XCTAssertNotNil(WorkoutFlow.currentEntry(of: session)?.exercise)
    }

    func testSettingsListShowsActiveMarksUntilTheyExpire() throws {
        let gym = GymEditing.createGym(named: "Downtown", at: downtown, in: context)
        let equipment = try context.fetch(FetchDescriptor<Equipment>(sortBy: [SortDescriptor(\.name)]))
        let now = Date.now
        let fresh = EquipmentUnavailability(gym: nil, equipment: equipment[0], markedAt: now.addingTimeInterval(-86_400))
        let stale = EquipmentUnavailability(gym: nil, equipment: equipment[1], markedAt: now.addingTimeInterval(-8 * 86_400))
        for row in [fresh, stale] {
            context.insert(row)
            gym.unavailableEquipment.append(row)
        }

        let items = GymEditing.unavailableEquipment(at: gym, now: now)
        XCTAssertEqual(items.map(\.name), [equipment[0].name])
        XCTAssertEqual(items.first?.expiresAt, fresh.markedAt.addingTimeInterval(EquipmentAvailability.defaultWindow))
    }

    func testClearOneAndClearAll() throws {
        let gym = GymEditing.createGym(named: "Downtown", at: downtown, in: context)
        let equipment = try context.fetch(FetchDescriptor<Equipment>(sortBy: [SortDescriptor(\.name)]))
        for item in equipment.prefix(3) {
            let row = EquipmentUnavailability(gym: nil, equipment: item, markedAt: .now)
            context.insert(row)
            gym.unavailableEquipment.append(row)
        }

        let first = try XCTUnwrap(GymEditing.unavailableEquipment(at: gym).first)
        let clearedID = try XCTUnwrap(first.row.equipment?.id)
        GymEditing.clear(first.row, in: context)
        XCTAssertEqual(GymEditing.unavailableEquipment(at: gym).count, 2)
        XCTAssertFalse(WorkoutFlow.unavailableEquipment(at: gym, now: .now).contains(clearedID))

        GymEditing.clearAll(at: gym, in: context)
        XCTAssertTrue(GymEditing.unavailableEquipment(at: gym).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EquipmentUnavailability>()), 0)
    }

    // MARK: Helpers

    private func liftingSession(at gym: Gym?) throws -> WorkoutSession {
        let split = SplitEditing.createSplit(named: "PPL", in: context)
        let push = SplitEditing.addDay(named: "Push", to: split, in: context)
        let id = "horizontal-press"
        let movementType = try XCTUnwrap(context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first)
        SplitEditing.addSlot(movementType, to: push, in: context)
        let session = WorkoutFlow.start(day: push, of: split, gym: gym, in: context, using: &rng)
        WorkoutFlow.skipWarmup(session, in: context)
        return session
    }

    /// Swaps the top card to a horizontal press that needs equipment (none of `avoiding`) and swipes
    /// it down. Returns that exercise's equipment.
    @discardableResult
    private func swipeDownOnEquipment(in session: WorkoutSession, avoiding: Set<String> = []) throws -> Set<String> {
        let all = try context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.id)]))
        let exercise = try XCTUnwrap(all.first { exercise in
            let equipment = Set(exercise.equipment.map(\.id))
            return exercise.movementType?.id == "horizontal-press" && !equipment.isEmpty && equipment.isDisjoint(with: avoiding)
        })
        XCTAssertEqual(WorkoutFlow.swapCurrent(to: exercise.id, in: session, context: context), .applied)
        XCTAssertEqual(WorkoutFlow.swipe(.down, in: session, context: context, using: &rng).result, .applied)
        return Set(exercise.equipment.map(\.id))
    }
}
