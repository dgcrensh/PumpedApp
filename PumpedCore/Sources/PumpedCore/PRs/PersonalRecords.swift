/// A personal record set in a workout (spec §9).
public enum PersonalRecord: Equatable, Hashable, Sendable {
    /// Heaviest weight ever lifted for this exercise.
    case heaviestWeight(Double)
    /// Best estimated one-rep max (Epley).
    case bestEstimatedOneRepMax(Double)
    /// Most reps ever done at this exact weight.
    case mostReps(Int, atWeight: Double)

    /// "Heaviest weight: 185 lb", "Best est. 1RM: 216 lb", "Most reps at 135 lb: 10".
    public var summary: String {
        switch self {
        case let .heaviestWeight(weight):
            "Heaviest weight: \(SetValues.format(weight)) lb"
        case let .bestEstimatedOneRepMax(e1RM):
            "Best est. 1RM: \(SetValues.format(e1RM.rounded())) lb"
        case let .mostReps(reps, weight):
            "Most reps at \(weight == 0 ? "bodyweight" : "\(SetValues.format(weight)) lb"): \(reps)"
        }
    }
}

/// PR math over plain set values, so it's testable anywhere.
public enum PersonalRecords {
    /// Epley: `w × (1 + reps/30)`. A single rep is the weight itself.
    public static func estimatedOneRepMax(_ set: SetValues) -> Double {
        set.reps <= 1 ? set.weightLb : set.weightLb * (1 + Double(set.reps) / 30)
    }

    /// The records `today`'s sets beat compared with every earlier set of the same exercise.
    ///
    /// Only the best of today counts per kind (one heaviest-weight PR, one 1RM PR, one most-reps PR
    /// per weight). An exercise done for the first time sets no PRs, since there's nothing to beat.
    /// Bodyweight sets (0 lb) only count toward most reps.
    public static func hits(today: [SetValues], history: [SetValues]) -> [PersonalRecord] {
        guard !today.isEmpty, !history.isEmpty else { return [] }
        var records: [PersonalRecord] = []

        let previousHeaviest = history.map(\.weightLb).max() ?? 0
        if let heaviest = today.map(\.weightLb).max(), heaviest > 0, heaviest > previousHeaviest {
            records.append(.heaviestWeight(heaviest))
        }

        let previousE1RM = history.map(estimatedOneRepMax).max() ?? 0
        if let best = today.map(estimatedOneRepMax).max(), best > 0, best > previousE1RM + 0.000_1 {
            records.append(.bestEstimatedOneRepMax(best))
        }

        // Most reps at a weight only means something when that weight was done before; a new
        // weight is already covered by the heaviest-weight record.
        let previousReps = Dictionary(history.map { ($0.weightLb, $0.reps) }, uniquingKeysWith: max)
        let todayReps = Dictionary(today.map { ($0.weightLb, $0.reps) }, uniquingKeysWith: max)
        for weight in todayReps.keys.sorted() {
            guard let reps = todayReps[weight], let before = previousReps[weight], reps > before else { continue }
            records.append(.mostReps(reps, atWeight: weight))
        }
        return records
    }
}
