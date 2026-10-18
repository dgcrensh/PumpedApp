/// How demanding an exercise is. Sets the default rest timer (spec §3, §6.2).
public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case heavyCompound
    case compound
    case isolation

    /// Default rest duration in seconds before the user customizes it in Settings.
    public var defaultRestSeconds: Int {
        switch self {
        case .heavyCompound: 180
        case .compound: 120
        case .isolation: 60
        }
    }

    public var displayName: String {
        switch self {
        case .heavyCompound: "Heavy compound"
        case .compound: "Compound"
        case .isolation: "Isolation"
        }
    }
}
