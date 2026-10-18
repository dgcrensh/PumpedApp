/// Every constant the variation selection algorithm uses (spec §7), kept together for tuning.
public struct SelectionTuning: Equatable, Codable, Sendable {
    /// Multiplier for exercises the user has liked.
    public var likeBoost: Double
    /// Multiplier for exercises done in any of the last `familiarityWindow` workouts of the movement.
    /// This is what keeps a "stable core" without hard anchors.
    public var familiarityBoost: Double
    /// How many recent workouts of a movement type count toward familiarity.
    public var familiarityWindow: Int
    /// Multiplier for the exercise done in the very last workout of the movement, for gentle variety.
    public var repeatDamping: Double

    public init(
        likeBoost: Double = 2.0,
        familiarityBoost: Double = 1.5,
        familiarityWindow: Int = 5,
        repeatDamping: Double = 0.75
    ) {
        self.likeBoost = likeBoost
        self.familiarityBoost = familiarityBoost
        self.familiarityWindow = familiarityWindow
        self.repeatDamping = repeatDamping
    }

    public static let `default` = SelectionTuning()
}
