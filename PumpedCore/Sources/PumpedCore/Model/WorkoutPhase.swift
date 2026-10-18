/// The phases a workout session moves through (spec §6).
public enum WorkoutPhase: String, Codable, CaseIterable, Sendable {
    case warmup
    case lifting
    case cooldown
    case complete
}

/// Whether a card in the lifting stack is still to do or finished for today.
public enum EntryStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case done
}
