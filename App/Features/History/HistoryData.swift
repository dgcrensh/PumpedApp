import Foundation
import OSLog
import PumpedCore
import SwiftData

/// What an exercise detail screen covers: one variation, or every variation of a movement type
/// (spec §9).
enum ProgressScope: Hashable {
    case exercise(String)
    case movementType(String)
}

/// One finished workout's sets for an exercise detail screen.
struct ExerciseWorkout: Identifiable {
    let session: WorkoutSession
    /// Names of the exercises the sets came from, in slot order (one unless the scope is a
    /// movement type).
    let exerciseNames: [String]
    let sets: [SetValues]

    var id: PersistentIdentifier { session.persistentModelID }
    var dated: DatedSets { DatedSets(date: session.startedAt, sets: sets) }
}

/// History reads and edits (spec §9), kept out of the views so they can be unit tested. PRs and
/// chart points are always derived from the stored sets, so edits and deletes recompute them.
@MainActor
enum HistoryData {
    private static let logger = Logger(subsystem: "com.dgcrensh.pumped", category: "History")

    /// Finished workouts that trained something in `scope`, newest first.
    static func workouts(_ scope: ProgressScope, in context: ModelContext) -> [ExerciseWorkout] {
        WorkoutFlow.finishedSessions(in: context).compactMap { session -> ExerciseWorkout? in
            let entries = session.entries
                .filter { entry -> Bool in
                    guard !entry.sets.isEmpty, let exercise = entry.exercise else { return false }
                    return matches(exercise, scope)
                }
                .sorted { $0.slotOrder < $1.slotOrder }
            guard !entries.isEmpty else { return nil }
            var names: [String] = []
            for name in entries.compactMap({ $0.exercise?.name }) where !names.contains(name) {
                names.append(name)
            }
            return ExerciseWorkout(
                session: session,
                exerciseNames: names,
                sets: entries.flatMap(\.orderedSets).map(WorkoutFlow.values)
            )
        }
    }

    /// Chart points for `scope`, oldest first.
    static func progress(_ scope: ProgressScope, in context: ModelContext) -> [ProgressPoint] {
        ExerciseProgress.points(workouts(scope, in: context).map(\.dated))
    }

    /// The exercise's current bests.
    static func records(of exerciseID: String, in context: ModelContext) -> RecordBook {
        RecordBook(sets: workouts(.exercise(exerciseID), in: context).flatMap(\.sets))
    }

    /// Every PR the exercise has set, newest first.
    static func prTimeline(of exerciseID: String, in context: ModelContext) -> [PREvent] {
        Array(PersonalRecords.timeline(workouts(.exercise(exerciseID), in: context).map(\.dated)).reversed())
    }

    /// PRs set in one workout, against every workout before it.
    static func prs(in session: WorkoutSession, context: ModelContext) -> [WorkoutSummary.PRHit] {
        WorkoutFlow.summary(of: session, in: context).prs
    }

    /// Exercises with at least one set in a finished workout, by name.
    static func trainedExercises(in context: ModelContext) -> [Exercise] {
        var seen = Set<String>()
        var exercises: [Exercise] = []
        for session in WorkoutFlow.finishedSessions(in: context) {
            for entry in session.entries where !entry.sets.isEmpty {
                guard let exercise = entry.exercise, seen.insert(exercise.id).inserted else { continue }
                exercises.append(exercise)
            }
        }
        return exercises.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Editing

    /// Changes a logged set after the fact. Weight is clamped at 0 (bodyweight), reps at 1.
    static func update(_ set: SetLog, to values: SetValues, in context: ModelContext) {
        set.reps = max(values.reps, 1)
        set.weightLb = max(values.weightLb, 0)
        save(context)
    }

    static func delete(_ set: SetLog, in context: ModelContext) {
        WorkoutFlow.deleteSet(set, in: context)
    }

    /// Deletes a finished workout with its warmup and sets. The split doesn't move back.
    static func delete(_ session: WorkoutSession, in context: ModelContext) {
        context.delete(session)
        save(context)
    }

    // MARK: Helpers

    private static func matches(_ exercise: Exercise, _ scope: ProgressScope) -> Bool {
        switch scope {
        case let .exercise(id): exercise.id == id
        case let .movementType(id): exercise.movementType?.id == id
        }
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logger.error("Saving history failed: \(String(describing: error), privacy: .public)")
            assertionFailure("Saving history failed: \(error)")
        }
    }
}
