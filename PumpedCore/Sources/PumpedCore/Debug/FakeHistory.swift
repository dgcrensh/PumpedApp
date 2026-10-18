import Foundation

/// Months of plausible past workouts, for trying out charts and selection weighting in a debug
/// build (plan M9). Pure values: the app writes them to SwiftData.
///
/// Workouts walk a split's days in order. Each slot is filled by `VariationSelector` against the
/// history generated so far, so the weighting (likes, familiarity, repeat damping) shapes which
/// variations recur, the same way it does for real workouts. Weights creep up over time with the
/// occasional deload.
public enum FakeHistory {
    public struct Workout: Equatable, Sendable {
        public var startedAt: Date
        public var endedAt: Date
        /// Index into the `days` passed to `generate`.
        public var dayIndex: Int
        public var entries: [Entry]
    }

    public struct Entry: Equatable, Sendable {
        /// The slot's movement type id.
        public var movementType: String
        public var exerciseID: String
        public var isSubstitute: Bool
        public var sets: [LoggedSet]
    }

    public struct LoggedSet: Equatable, Sendable {
        public var values: SetValues
        public var loggedAt: Date
    }

    /// Generates `weeks` of workouts ending before `end`, oldest first.
    ///
    /// - Parameters:
    ///   - days: each split day's movement type ids, in cycle order. Empty days are skipped.
    ///   - selector: the library and the user's hidden and liked flags. Its history is replaced by
    ///     the generated workouts as they're made.
    ///   - exerciseTypes: exercise id → type, which sets the starting weight and rep range.
    public static func generate(
        days: [[String]],
        selector: VariationSelector,
        exerciseTypes: [String: ExerciseType],
        endingAt end: Date,
        weeks: Int = 26,
        workoutsPerWeek: Int = 4,
        using rng: inout some RandomNumberGenerator
    ) -> [Workout] {
        let days = days.enumerated().filter { !$0.element.isEmpty }
        guard !days.isEmpty, weeks > 0, workoutsPerWeek > 0 else { return [] }

        var selector = selector
        var pastWorkouts: [[String: Set<String>]] = []
        var progress: [String: Progress] = [:]
        var workouts: [Workout] = []

        let count = weeks * workoutsPerWeek
        let spacing = Double(weeks * 7) / Double(count) * day
        let firstStart = end.addingTimeInterval(-Double(weeks * 7) * day)

        for index in 0..<count {
            // Evenings, give or take a few hours.
            let jitter = Double.random(in: -3...3, using: &rng) * hour
            let startedAt = firstStart.addingTimeInterval(Double(index) * spacing + 18 * hour + jitter)
            guard startedAt < end else { break }
            let (dayIndex, slots) = days[index % days.count]

            selector.history = SelectionHistory(newestFirst: Array(pastWorkouts.reversed()))
            var taken: Set<String> = []
            var clock = startedAt.addingTimeInterval(10 * 60)
            var entries: [Entry] = []
            for movementType in slots {
                let fill = selector.select(for: movementType, excluding: taken, using: &rng)
                guard let exerciseID = fill.exerciseID else { continue }
                taken.insert(exerciseID)
                let type = exerciseTypes[exerciseID] ?? .compound
                let isBodyweight = selector.exercise(exerciseID)?.equipment.isEmpty ?? false
                var state = progress[exerciseID] ?? Progress(type: type, isBodyweight: isBodyweight)
                var sets: [LoggedSet] = []
                for values in state.nextSession(using: &rng) {
                    clock = clock.addingTimeInterval(Double(type.defaultRestSeconds) + 45)
                    sets.append(LoggedSet(values: values, loggedAt: clock))
                }
                progress[exerciseID] = state
                entries.append(Entry(movementType: movementType, exerciseID: exerciseID, isSubstitute: fill.isSubstitute, sets: sets))
            }

            var done: [String: Set<String>] = [:]
            for entry in entries {
                // History is keyed by the exercise's own movement type, as the app does it.
                let movementType = selector.exercise(entry.exerciseID)?.movementType ?? entry.movementType
                done[movementType, default: []].insert(entry.exerciseID)
            }
            pastWorkouts.append(done)

            let endedAt = clock.addingTimeInterval(15 * 60)
            workouts.append(Workout(startedAt: startedAt, endedAt: min(endedAt, end), dayIndex: dayIndex, entries: entries))
        }
        return workouts
    }

    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86_400

    /// One exercise's working weight over time.
    private struct Progress {
        let type: ExerciseType
        let isBodyweight: Bool
        var weightLb: Double
        var sessions = 0

        init(type: ExerciseType, isBodyweight: Bool) {
            self.type = type
            self.isBodyweight = isBodyweight
            if isBodyweight {
                weightLb = 0
            } else {
                weightLb = switch type {
                case .heavyCompound: 135
                case .compound: 65
                case .isolation: 20
                }
            }
        }

        private var baseReps: Int {
            switch type {
            case .heavyCompound: 5
            case .compound: 8
            case .isolation: 12
            }
        }

        /// This session's sets, then moves the working weight on: usually up 5 lb, sometimes held,
        /// and every ninth session a deload.
        mutating func nextSession(using rng: inout some RandomNumberGenerator) -> [SetValues] {
            let setCount = Int.random(in: 3...4, using: &rng)
            var reps = baseReps + (isBodyweight ? 4 : 0) + Int.random(in: 0...2, using: &rng)
            var sets: [SetValues] = []
            for _ in 0..<setCount {
                sets.append(SetValues(reps: reps, weightLb: weightLb))
                if Bool.random(using: &rng) { reps = max(reps - 1, 1) }
            }
            sessions += 1
            if !isBodyweight {
                if sessions % 9 == 0 {
                    weightLb = max(((weightLb * 0.9) / 5).rounded() * 5, 5)
                } else if Double.random(in: 0..<1, using: &rng) < 0.6 {
                    weightLb += 5
                }
            }
            return sets
        }
    }
}
