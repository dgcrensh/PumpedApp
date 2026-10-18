import Foundation

/// One workout's sets of an exercise (or of a movement type), in the order they were logged.
public struct DatedSets: Equatable, Sendable {
    public var date: Date
    public var sets: [SetValues]

    public init(date: Date, sets: [SetValues]) {
        self.date = date
        self.sets = sets
    }
}

/// The best numbers ever logged for an exercise (spec §9): heaviest weight, best e1RM and the most
/// reps at each weight. Always derived from the sets themselves, so editing or deleting a set
/// recomputes them.
public struct RecordBook: Equatable, Sendable {
    /// The heaviest set, with the most reps done at that weight. Nil when only bodyweight was logged.
    public var heaviest: SetValues?
    /// The set with the best Epley estimate.
    public var bestEstimatedOneRepMax: SetValues?
    /// Most reps at each weight, heaviest weight first.
    public var mostReps: [SetValues]

    public init(sets: [SetValues]) {
        let weighted = sets.filter { $0.weightLb > 0 }
        heaviest = weighted.max { ($0.weightLb, $0.reps) < ($1.weightLb, $1.reps) }
        bestEstimatedOneRepMax = weighted.max {
            PersonalRecords.estimatedOneRepMax($0) < PersonalRecords.estimatedOneRepMax($1)
        }
        mostReps = Dictionary(sets.map { ($0.weightLb, $0.reps) }, uniquingKeysWith: max)
            .map { SetValues(reps: $0.value, weightLb: $0.key) }
            .sorted { $0.weightLb > $1.weightLb }
    }

    public var isEmpty: Bool { mostReps.isEmpty }
}

/// A PR and the workout it was set in.
public struct PREvent: Equatable, Sendable {
    public var date: Date
    public var record: PersonalRecord

    public init(date: Date, record: PersonalRecord) {
        self.date = date
        self.record = record
    }
}

extension PersonalRecords {
    /// Every PR in an exercise's history, oldest first: each workout's sets measured against all
    /// the workouts before it (spec §9). Workouts are sorted by date first.
    public static func timeline(_ workouts: [DatedSets]) -> [PREvent] {
        var earlier: [SetValues] = []
        var events: [PREvent] = []
        for workout in workouts.sorted(by: { $0.date < $1.date }) {
            events += hits(today: workout.sets, history: earlier).map { PREvent(date: workout.date, record: $0) }
            earlier += workout.sets
        }
        return events
    }

    /// The records a set just logged breaks, for the card's PR badge: measured against every earlier
    /// workout and the sets already logged today, so only the set that moves a record gets it.
    public static func newRecords(set: SetValues, earlierToday: [SetValues], history: [SetValues]) -> [PersonalRecord] {
        hits(today: [set], history: history + earlierToday)
    }
}

/// One point per workout on the exercise progress chart (spec §9).
public struct ProgressPoint: Equatable, Sendable {
    public var date: Date
    /// The heaviest set of the workout; the most reps breaks a tie.
    public var topSet: SetValues
    /// The workout's best Epley estimate.
    public var estimatedOneRepMax: Double

    public var topSetWeightLb: Double { topSet.weightLb }
}

public enum ExerciseProgress {
    /// Chart points, oldest first. Workouts with no sets are skipped.
    public static func points(_ workouts: [DatedSets]) -> [ProgressPoint] {
        workouts
            .sorted { $0.date < $1.date }
            .compactMap { workout in
                guard let top = workout.sets.max(by: { ($0.weightLb, $0.reps) < ($1.weightLb, $1.reps) }) else { return nil }
                let e1RM = workout.sets.map(PersonalRecords.estimatedOneRepMax).max() ?? 0
                return ProgressPoint(date: workout.date, topSet: top, estimatedOneRepMax: e1RM)
            }
    }
}
