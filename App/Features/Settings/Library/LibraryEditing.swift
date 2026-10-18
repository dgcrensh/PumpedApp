import Foundation
import PumpedCore
import SwiftData

/// Settings' changes to the exercise library (spec §4, §10): hidden and liked exercises, custom
/// exercises and custom stretches. Kept out of the views so they can be unit tested.
@MainActor
enum LibraryEditing {
    // MARK: Hidden and liked

    static func setHidden(_ exercise: Exercise, _ hidden: Bool, in context: ModelContext) {
        exercise.isHidden = hidden
        save(context)
    }

    static func setLiked(_ exercise: Exercise, _ liked: Bool, in context: ModelContext) {
        exercise.isLiked = liked
        save(context)
    }

    // MARK: Custom exercises

    /// What the custom exercise form edits.
    struct ExerciseDraft: Equatable {
        var name = ""
        var movementTypeID: String?
        /// Empty means bodyweight.
        var equipmentIDs: Set<String> = []
        var exerciseType: ExerciseType = .compound
        /// Muscle group ids. Empty means the movement type's primary muscles.
        var muscles: Set<String> = []

        var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
        var isValid: Bool { !trimmedName.isEmpty && movementTypeID != nil }
    }

    static func draft(of exercise: Exercise) -> ExerciseDraft {
        ExerciseDraft(
            name: exercise.name,
            movementTypeID: exercise.movementType?.id,
            equipmentIDs: Set(exercise.equipment.map(\.id)),
            exerciseType: exercise.exerciseType,
            muscles: Set(exercise.muscles)
        )
    }

    /// Adds a custom exercise. The selector picks it like any library exercise. Nil when the draft
    /// has no name or movement type.
    @discardableResult
    static func createExercise(_ draft: ExerciseDraft, in context: ModelContext) -> Exercise? {
        guard draft.isValid else { return nil }
        let exercise = Exercise(id: "custom-\(UUID().uuidString)", name: draft.trimmedName, exerciseType: draft.exerciseType, isCustom: true)
        context.insert(exercise)
        apply(draft, to: exercise, in: context)
        save(context)
        return exercise
    }

    /// Edits a custom exercise. Library exercises come from the seed and aren't edited here.
    @discardableResult
    static func update(_ exercise: Exercise, with draft: ExerciseDraft, in context: ModelContext) -> Bool {
        guard exercise.isCustom, draft.isValid else { return false }
        exercise.name = draft.trimmedName
        apply(draft, to: exercise, in: context)
        save(context)
        return true
    }

    /// Only custom exercises that were never logged can be deleted; history keeps the rest, and
    /// they can be hidden instead.
    static func canDelete(_ exercise: Exercise, in context: ModelContext) -> Bool {
        guard exercise.isCustom else { return false }
        guard let entries = try? context.fetch(FetchDescriptor<WorkoutEntry>()) else { return false }
        return !entries.contains { $0.exercise === exercise }
    }

    @discardableResult
    static func deleteExercise(_ exercise: Exercise, in context: ModelContext) -> Bool {
        guard canDelete(exercise, in: context) else { return false }
        context.delete(exercise)
        save(context)
        return true
    }

    private static func apply(_ draft: ExerciseDraft, to exercise: Exercise, in context: ModelContext) {
        let movementType = draft.movementTypeID.flatMap { id in
            try? context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first
        }
        exercise.movementType = movementType
        exercise.exerciseType = draft.exerciseType
        let equipment = (try? context.fetch(FetchDescriptor<Equipment>())) ?? []
        exercise.equipment = equipment.filter { draft.equipmentIDs.contains($0.id) }.sorted { $0.id < $1.id }
        exercise.muscles = draft.muscles.isEmpty ? (movementType?.primaryMuscles ?? []) : draft.muscles.sorted()
    }

    // MARK: Custom stretches

    static let stretchDurationRange = 10...300

    /// Adds a custom stretch for stretch sequences. Nil for a blank name.
    @discardableResult
    static func createStretch(named name: String, durationSec: Int, in context: ModelContext) -> Stretch? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let stretch = Stretch(id: "custom-\(UUID().uuidString)", name: name, defaultDurationSec: clamp(durationSec), isCustom: true)
        context.insert(stretch)
        save(context)
        return stretch
    }

    /// Renames a custom stretch and changes its default hold. Sequences keep their own holds.
    @discardableResult
    static func updateStretch(_ stretch: Stretch, name: String, durationSec: Int, in context: ModelContext) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stretch.isCustom, !name.isEmpty else { return false }
        stretch.name = name
        stretch.defaultDurationSec = clamp(durationSec)
        save(context)
        return true
    }

    /// Sequences that hold the stretch, so the delete prompt can name them.
    static func sequences(using stretch: Stretch, in context: ModelContext) -> [StretchSequence] {
        let sequences = (try? context.fetch(FetchDescriptor<StretchSequence>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return sequences.filter { sequence in sequence.items.contains { $0.stretch === stretch } }
    }

    /// Deletes a custom stretch and takes it out of the sequences that held it.
    static func deleteStretch(_ stretch: Stretch, in context: ModelContext) {
        guard stretch.isCustom else { return }
        for sequence in sequences(using: stretch, in: context) {
            let doomed = sequence.items.filter { $0.stretch === stretch }
            sequence.items.removeAll { item in doomed.contains { $0 === item } }
            for item in doomed { context.delete(item) }
            for (position, item) in sequence.orderedItems.enumerated() { item.order = position }
        }
        context.delete(stretch)
        save(context)
    }

    private static func clamp(_ seconds: Int) -> Int {
        min(max(seconds, stretchDurationRange.lowerBound), stretchDurationRange.upperBound)
    }

    private static func save(_ context: ModelContext) {
        try? context.save()
    }
}
