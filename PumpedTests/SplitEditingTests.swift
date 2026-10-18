import SwiftData
import XCTest
@testable import Pumped

@MainActor
final class SplitEditingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try PumpedStore.makeContainer(inMemory: true)
        SeedImporter.importBundledSeedIfNeeded(into: context)
    }

    func testFirstSplitIsActiveAndSetActiveIsExclusive() throws {
        let first = SplitEditing.createSplit(named: "PPL", in: context)
        let second = SplitEditing.createSplit(named: "Upper/Lower", in: context)
        XCTAssertTrue(first.isActive)
        XCTAssertFalse(second.isActive)

        SplitEditing.setActive(second, in: context)
        XCTAssertFalse(first.isActive)
        XCTAssertTrue(second.isActive)
    }

    func testDeletingActiveSplitActivatesAnother() throws {
        let first = SplitEditing.createSplit(named: "A", in: context)
        let second = SplitEditing.createSplit(named: "B", in: context)
        try context.save()

        SplitEditing.deleteSplit(first, in: context)
        try context.save()
        XCTAssertTrue(second.isActive)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Split>()), 1)
    }

    func testDeletingSplitDeletesItsDaysAndSlots() throws {
        let split = try pushPullLegs()
        try context.save()
        SplitEditing.deleteSplit(split, in: context)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SplitDay>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MovementSlot>()), 0)
    }

    func testNewDayGetsDefaultCooldown() throws {
        let split = SplitEditing.createSplit(named: "PPL", in: context)
        let day = SplitEditing.addDay(named: "Push", to: split, in: context)
        XCTAssertEqual(day.stretchSequence?.id, SplitEditing.defaultStretchSequenceID)
        XCTAssertNil(day.defaultCardio)
    }

    func testReorderingDaysKeepsNextDay() throws {
        let split = try pushPullLegs()
        SplitEditing.setNextDay(split.orderedDays[1], of: split)
        XCTAssertEqual(SplitEditing.nextDay(of: split)?.name, "Pull")

        // Move Push to the end: Pull, Legs, Push.
        SplitEditing.moveDays(of: split, fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(split.orderedDays.map(\.name), ["Pull", "Legs", "Push"])
        XCTAssertEqual(SplitEditing.nextDay(of: split)?.name, "Pull")
        XCTAssertEqual(SplitCycleText.nextUp(for: split), "Next up: Pull, day 1 of 3")
    }

    func testDeletingNextDayMovesToFollowingDay() throws {
        let split = try pushPullLegs()
        SplitEditing.setNextDay(split.orderedDays[1], of: split)
        SplitEditing.deleteDays(at: [1], from: split, in: context)
        try context.save()

        XCTAssertEqual(split.orderedDays.map(\.name), ["Push", "Legs"])
        XCTAssertEqual(split.orderedDays.map(\.order), [0, 1])
        XCTAssertEqual(SplitEditing.nextDay(of: split)?.name, "Legs")
    }

    func testSlotsAllowDuplicatesAndReorder() throws {
        let split = SplitEditing.createSplit(named: "PPL", in: context)
        let day = SplitEditing.addDay(named: "Push", to: split, in: context)
        let press = try movementType("horizontal-press")
        let fly = try movementType("chest-fly")

        SplitEditing.addSlot(press, to: day, in: context)
        SplitEditing.addSlot(fly, to: day, in: context)
        SplitEditing.addSlot(press, to: day, in: context)
        XCTAssertEqual(slotIDs(day), ["horizontal-press", "chest-fly", "horizontal-press"])

        SplitEditing.moveSlots(of: day, fromOffsets: [1], toOffset: 3)
        XCTAssertEqual(slotIDs(day), ["horizontal-press", "horizontal-press", "chest-fly"])

        SplitEditing.deleteSlots(at: [0], from: day, in: context)
        try context.save()
        XCTAssertEqual(slotIDs(day), ["horizontal-press", "chest-fly"])
        XCTAssertEqual(day.orderedSlots.map(\.order), [0, 1])
    }

    func testDuplicatingDefaultSequenceMakesEditableCopy() throws {
        let source = try XCTUnwrap(context.fetch(FetchDescriptor<StretchSequence>(predicate: #Predicate { $0.id == "full-body" })).first)
        let copy = SplitEditing.duplicateSequence(source, in: context)
        try context.save()

        XCTAssertFalse(copy.isDefault)
        XCTAssertEqual(copy.name, "Full Body copy")
        XCTAssertEqual(copy.orderedItems.map { $0.stretch?.id }, source.orderedItems.map { $0.stretch?.id })
        XCTAssertEqual(copy.orderedItems.map(\.durationSec), source.orderedItems.map(\.durationSec))

        // Editing the copy leaves the default alone.
        SplitEditing.deleteStretches(at: [0], from: copy, in: context)
        copy.orderedItems[0].durationSec = 90
        try context.save()
        XCTAssertEqual(copy.items.count, source.items.count - 1)
        XCTAssertNotEqual(source.orderedItems[1].durationSec, 90)
    }

    func testDefaultSequencesAreReadOnly() throws {
        let source = try XCTUnwrap(context.fetch(FetchDescriptor<StretchSequence>(predicate: #Predicate { $0.id == "full-body" })).first)
        let count = source.items.count
        let stretch = try XCTUnwrap(context.fetch(FetchDescriptor<Stretch>()).first)
        XCTAssertNil(SplitEditing.addStretch(stretch, to: source, in: context))
        SplitEditing.deleteStretches(at: [0], from: source, in: context)
        SplitEditing.deleteSequence(source, in: context)
        try context.save()
        XCTAssertEqual(source.items.count, count)
        XCTAssertFalse(source.isDeleted)
    }

    func testCustomSequenceEditing() throws {
        let sequence = SplitEditing.createSequence(named: "Hips", in: context)
        let stretches = try context.fetch(FetchDescriptor<Stretch>(sortBy: [SortDescriptor(\.name)]))
        let a = try XCTUnwrap(SplitEditing.addStretch(stretches[0], to: sequence, in: context))
        let b = try XCTUnwrap(SplitEditing.addStretch(stretches[1], to: sequence, in: context))
        XCTAssertEqual(a.durationSec, stretches[0].defaultDurationSec)

        SplitEditing.moveStretches(of: sequence, fromOffsets: [1], toOffset: 0)
        XCTAssertTrue(sequence.orderedItems.first === b)
    }

    func testDeletingSequenceClearsItFromDays() throws {
        let split = SplitEditing.createSplit(named: "PPL", in: context)
        let day = SplitEditing.addDay(named: "Push", to: split, in: context)
        let sequence = SplitEditing.createSequence(named: "Mine", in: context)
        day.stretchSequence = sequence
        try context.save()

        SplitEditing.deleteSequence(sequence, in: context)
        try context.save()
        XCTAssertNil(day.stretchSequence)
    }

    // MARK: Helpers

    private func pushPullLegs() throws -> Split {
        let split = SplitEditing.createSplit(named: "PPL", in: context)
        for name in ["Push", "Pull", "Legs"] {
            SplitEditing.addDay(named: name, to: split, in: context)
        }
        return split
    }

    private func movementType(_ id: String) throws -> MovementType {
        try XCTUnwrap(context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first)
    }

    private func slotIDs(_ day: SplitDay) -> [String?] {
        day.orderedSlots.map { $0.movementType?.id }
    }
}
