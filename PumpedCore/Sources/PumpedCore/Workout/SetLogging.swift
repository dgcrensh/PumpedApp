/// A logged set's numbers, as the card shows and prefills them.
public struct SetValues: Equatable, Codable, Sendable {
    public var reps: Int
    public var weightLb: Double

    public init(reps: Int, weightLb: Double) {
        self.reps = reps
        self.weightLb = weightLb
    }

    /// What the steppers show for an exercise with no history.
    public static let fallback = SetValues(reps: 8, weightLb: 0)

    /// "8×135", or "8×137.5". Bodyweight (0 lb) reads "8×BW".
    public var summary: String {
        "\(reps)×\(weightLb == 0 ? "BW" : SetValues.format(weightLb))"
    }

    public static func format(_ weightLb: Double) -> String {
        weightLb.rounded() == weightLb ? String(Int(weightLb)) : String(weightLb)
    }
}

/// How the card's reps and weight steppers are filled (spec §6.2): never auto-incremented.
public enum SetPrefill {
    /// The next set repeats today's last set. The first set of the day repeats the first set from the
    /// last session of this exercise. With no history, `SetValues.fallback`.
    public static func values(today: [SetValues], lastSession: [SetValues]) -> SetValues {
        today.last ?? lastSession.first ?? .fallback
    }

    /// One step of the weight stepper and the "+5 lb" button.
    public static let weightStepLb = 5.0

    /// Weight after a stepper step, clamped at 0 (bodyweight).
    public static func stepWeight(_ weightLb: Double, by steps: Int) -> Double {
        max(weightLb + Double(steps) * weightStepLb, 0)
    }

    /// "Last time, Oct 12: 8×135, 8×135, 6×135" without the date part.
    public static func summary(_ sets: [SetValues]) -> String {
        sets.map(\.summary).joined(separator: ", ")
    }
}
