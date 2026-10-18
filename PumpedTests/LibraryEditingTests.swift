import PumpedCore
import SwiftData
import XCTest
@testable import Pumped

@MainActor
final class LibraryEditingTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var rng = SeededGenerator(seed: 11)

    override func setUp() async throws {
        container = try PumpedStore.makeContainer(inMemory: true)
        SeedImporter.importBundledSeedIfNeeded(into: context)
    }

    // MARK: Hidden and liked

    func testUnhideAndUnlike() throws {
        let bench = try exercise("barbell-bench-press")
        LibraryEditing.setHidden(bench, true, in: context)
        LibraryEditing.setLiked(bench, true, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.isHidden })).map(\.id), [bench.id])

        let selector = WorkoutFlow.makeSelector(gym: nil, now: .now, in: context)
        XCTAssertFalse(selector.weightedCandidates(for: "horizontal-press", excluding: []).contains { $0.id == bench.id })

        LibraryEditing.setHidden(bench, false, in: context)
        LibraryEditing.setLiked(bench, false, in: context)
        XCTAssertFalse(bench.isHidden)
        XCTAssertFalse(bench.isLiked)
        let after = WorkoutFlow.makeSelector(gym: nil, now: .now, in: context)
        XCTAssertTrue(after.weightedCandidates(for: "horizontal-press", excluding: []).contains { $0.id == bench.id })
    }

    // MARK: Custom exercises

    func testCreatedExerciseIsPickedForItsMovement() throws {
        var draft = LibraryEditing.ExerciseDraft(name: "  Landmine Press ", movementTypeID: "vertical-press")
        draft.equipmentIDs = ["barbell"]
        draft.exerciseType = .compound
        let custom = try XCTUnwrap(LibraryEditing.createExercise(draft, in: context))

        XCTAssertTrue(custom.isCustom)
        XCTAssertTrue(custom.id.hasPrefix("custom-"))
        XCTAssertEqual(custom.name, "Landmine Press")
        XCTAssertEqual(custom.movementType?.id, "vertical-press")
        XCTAssertEqual(custom.equipment.map(\.id), ["barbell"])
        XCTAssertEqual(custom.muscles, try movementType("vertical-press").primaryMuscles, "no muscles picked means the movement's")

        let selector = WorkoutFlow.makeSelector(gym: nil, now: .now, in: context)
        XCTAssertTrue(selector.weightedCandidates(for: "vertical-press", excluding: []).contains { $0.id == custom.id })
    }

    func testDraftNeedsANameAndMovement() {
        XCTAssertNil(LibraryEditing.createExercise(.init(name: "   ", movementTypeID: "squat"), in: context))
        XCTAssertNil(LibraryEditing.createExercise(.init(name: "Thing"), in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>(predicate: #Predicate { $0.isCustom })), 0)
    }

    func testEditingACustomExercise() throws {
        let custom = try XCTUnwrap(LibraryEditing.createExercise(.init(name: "Landmine Press", movementTypeID: "vertical-press"), in: context))
        var draft = LibraryEditing.draft(of: custom)
        draft.name = "Landmine Row"
        draft.movementTypeID = "horizontal-row"
        draft.equipmentIDs = ["barbell"]
        draft.muscles = ["lats"]
        draft.exerciseType = .heavyCompound
        XCTAssertTrue(LibraryEditing.update(custom, with: draft, in: context))
        XCTAssertEqual(custom.name, "Landmine Row")
        XCTAssertEqual(custom.movementType?.id, "horizontal-row")
        XCTAssertEqual(custom.muscles, ["lats"])
        XCTAssertEqual(custom.exerciseType, .heavyCompound)
        XCTAssertEqual(LibraryEditing.draft(of: custom), draft)

        let seeded = try exercise("barbell-bench-press")
        XCTAssertFalse(LibraryEditing.update(seeded, with: draft, in: context), "library exercises aren't edited")
        XCTAssertEqual(seeded.name, "Barbell Bench Press")
    }

    func testOnlyUnloggedCustomExercisesCanBeDeleted() throws {
        let unused = try XCTUnwrap(LibraryEditing.createExercise(.init(name: "Unused", movementTypeID: "squat"), in: context))
        XCTAssertTrue(LibraryEditing.deleteExercise(unused, in: context))
        XCTAssertFalse(try context.fetch(FetchDescriptor<Exercise>()).contains { $0.isCustom })

        let logged = try XCTUnwrap(LibraryEditing.createExercise(.init(name: "Logged", movementTypeID: "squat"), in: context))
        let session = WorkoutSession(phase: .complete)
        context.insert(session)
        let entry = WorkoutEntry(slotOrder: 0, movementTypeID: "squat", exercise: logged, stackPosition: -1)
        context.insert(entry)
        session.entries.append(entry)
        XCTAssertFalse(LibraryEditing.canDelete(logged, in: context))
        XCTAssertFalse(LibraryEditing.deleteExercise(logged, in: context))
        XCTAssertFalse(LibraryEditing.canDelete(try exercise("back-squat"), in: context), "library exercises stay")
    }

    // MARK: Custom stretches

    func testCustomStretchCanJoinASequence() throws {
        let stretch = try XCTUnwrap(LibraryEditing.createStretch(named: " Wall Calf Stretch ", durationSec: 45, in: context))
        XCTAssertTrue(stretch.isCustom)
        XCTAssertEqual(stretch.name, "Wall Calf Stretch")
        XCTAssertEqual(stretch.defaultDurationSec, 45)
        XCTAssertNil(LibraryEditing.createStretch(named: "  ", durationSec: 30, in: context))
        XCTAssertEqual(LibraryEditing.createStretch(named: "Long", durationSec: 9_999, in: context)?.defaultDurationSec, LibraryEditing.stretchDurationRange.upperBound)

        XCTAssertTrue(LibraryEditing.updateStretch(stretch, name: "Calf Stretch", durationSec: 60, in: context))
        XCTAssertEqual(stretch.name, "Calf Stretch")
        let seeded = try XCTUnwrap(context.fetch(FetchDescriptor<Stretch>()).first { !$0.isCustom })
        XCTAssertFalse(LibraryEditing.updateStretch(seeded, name: "Renamed", durationSec: 60, in: context))

        let sequence = SplitEditing.createSequence(named: "Mine", in: context)
        XCTAssertEqual(SplitEditing.addStretch(stretch, to: sequence, in: context)?.durationSec, 60)
    }

    func testDeletingAStretchTakesItOutOfSequences() throws {
        let custom = try XCTUnwrap(LibraryEditing.createStretch(named: "Calf Stretch", durationSec: 30, in: context))
        let other = try XCTUnwrap(context.fetch(FetchDescriptor<Stretch>()).first { !$0.isCustom })
        let sequence = SplitEditing.createSequence(named: "Mine", in: context)
        SplitEditing.addStretch(other, to: sequence, in: context)
        SplitEditing.addStretch(custom, to: sequence, in: context)
        SplitEditing.addStretch(other, to: sequence, in: context)
        XCTAssertEqual(LibraryEditing.sequences(using: custom, in: context).map(\.name), ["Mine"])

        LibraryEditing.deleteStretch(custom, in: context)
        XCTAssertEqual(sequence.orderedItems.count, 2)
        XCTAssertEqual(sequence.orderedItems.map(\.order), [0, 1])
        XCTAssertTrue(sequence.orderedItems.allSatisfy { $0.stretch === other })
        XCTAssertFalse(try context.fetch(FetchDescriptor<Stretch>()).contains { $0.isCustom })

        LibraryEditing.deleteStretch(other, in: context)
        XCTAssertFalse(other.isDeleted, "library stretches stay")
    }

    // MARK: Helpers

    private func exercise(_ id: String) throws -> Exercise {
        try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first)
    }

    private func movementType(_ id: String) throws -> MovementType {
        try XCTUnwrap(context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first)
    }
}
