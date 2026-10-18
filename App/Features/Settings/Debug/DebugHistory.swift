#if DEBUG
import Foundation
import PumpedCore
import SwiftData

/// Debug-only fake history (plan M9), for trying out charts and selection weighting.
///
/// Generated workouts are ordinary finished `WorkoutSession`s whose ids start with `idPrefix`, so
/// they can be told apart from real ones and removed again.
@MainActor
enum DebugHistory {
    static let idPrefix = "debug-"

    /// Used when there's no active split with movements.
    static let fallbackDays: [(name: String, movementTypes: [String])] = [
        ("Push", ["horizontal-press", "vertical-press", "chest-fly", "triceps-extension", "lateral-raise"]),
        ("Pull", ["vertical-pull", "horizontal-row", "rear-delt", "biceps-curl"]),
        ("Legs", ["squat", "hip-hinge", "lunge", "leg-curl", "calf-raise"]),
    ]

    /// Adds `weeks` of finished workouts ending now, walking the active split's days (or a
    /// push/pull/legs plan). Doesn't move the split's cycle. Returns how many were added.
    @discardableResult
    static func generate(
        weeks: Int = 26,
        now: Date = .now,
        in context: ModelContext,
        using rng: inout some RandomNumberGenerator
    ) -> Int {
        let split = try? context.fetch(FetchDescriptor<Split>(predicate: #Predicate { $0.isActive })).first
        let splitDays = split?.orderedDays.filter { !$0.slots.isEmpty } ?? []
        var days: [(day: SplitDay?, movementTypes: [String])] = []
        if splitDays.isEmpty {
            for fallback in fallbackDays { days.append((day: nil, movementTypes: fallback.movementTypes)) }
        } else {
            for day in splitDays { days.append((day: day, movementTypes: day.orderedSlots.compactMap { $0.movementType?.id })) }
        }

        var selector = WorkoutFlow.makeSelector(gym: nil, now: now, in: context)
        selector.history = .empty
        let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let exercises = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let workouts = FakeHistory.generate(
            days: days.map(\.movementTypes),
            selector: selector,
            exerciseTypes: exercises.mapValues(\.exerciseType),
            endingAt: now,
            weeks: weeks,
            using: &rng
        )
        for workout in workouts {
            let day = days[workout.dayIndex].day
            let session = WorkoutSession(
                id: idPrefix + UUID().uuidString,
                startedAt: workout.startedAt,
                split: day == nil ? nil : split,
                splitDay: day,
                phase: .complete
            )
            context.insert(session)
            session.endedAt = workout.endedAt
            session.cooldownCompleted = true
            for (slot, generated) in workout.entries.enumerated() {
                let entry = WorkoutEntry(
                    slotOrder: slot,
                    movementTypeID: generated.movementType,
                    exercise: exercises[generated.exerciseID],
                    stackPosition: -1,
                    isSubstitute: generated.isSubstitute
                )
                entry.status = .done
                context.insert(entry)
                session.entries.append(entry)
                for set in generated.sets {
                    let log = SetLog(reps: set.values.reps, weightLb: set.values.weightLb, loggedAt: set.loggedAt)
                    context.insert(log)
                    entry.sets.append(log)
                }
            }
        }
        try? context.save()
        return workouts.count
    }

    static func generatedSessions(in context: ModelContext) -> [WorkoutSession] {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return sessions.filter { $0.id.hasPrefix(idPrefix) }
    }

    /// Deletes every generated workout. Real workouts stay.
    @discardableResult
    static func removeGenerated(in context: ModelContext) -> Int {
        let sessions = generatedSessions(in: context)
        for session in sessions { context.delete(session) }
        try? context.save()
        return sessions.count
    }
}
#endif
