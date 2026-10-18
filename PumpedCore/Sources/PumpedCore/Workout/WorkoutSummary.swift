import Foundation

/// The numbers on the end-of-workout summary (spec §6.4).
public struct WorkoutSummary: Equatable, Sendable {
    /// One card's exercise and the sets logged on it today.
    public struct Exercise: Equatable, Sendable {
        public var name: String
        public var sets: [SetValues]
        /// Every earlier set of this exercise, for PRs.
        public var history: [SetValues]

        public init(name: String, sets: [SetValues], history: [SetValues] = []) {
            self.name = name
            self.sets = sets
            self.history = history
        }
    }

    public struct PRHit: Equatable, Sendable {
        public var exerciseName: String
        public var record: PersonalRecord
    }

    public var duration: TimeInterval
    /// Exercises with at least one set, in the order given.
    public var exerciseNames: [String]
    public var setCount: Int
    /// Total pounds moved: reps × weight over every set.
    public var volumeLb: Double
    public var prs: [PRHit]

    public init(startedAt: Date, endedAt: Date, exercises: [Exercise]) {
        let trained = exercises.filter { !$0.sets.isEmpty }
        duration = max(endedAt.timeIntervalSince(startedAt), 0)
        exerciseNames = trained.map(\.name)
        setCount = trained.reduce(0) { $0 + $1.sets.count }
        volumeLb = trained.flatMap(\.sets).reduce(0) { $0 + Double($1.reps) * $1.weightLb }
        prs = trained.flatMap { exercise in
            PersonalRecords.hits(today: exercise.sets, history: exercise.history)
                .map { PRHit(exerciseName: exercise.name, record: $0) }
        }
    }

    /// "1 h 5 min", "42 min", or "under a minute".
    public static func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 1 { return "under a minute" }
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
