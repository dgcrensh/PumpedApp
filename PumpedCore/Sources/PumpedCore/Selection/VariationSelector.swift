/// What a movement slot ended up holding.
public enum SlotFill: Equatable, Codable, Sendable {
    /// A variation of the slot's own movement type.
    case variation(exerciseID: String)
    /// An exercise of another movement type that hits the same muscles ("Substitute for <movement>").
    case substitute(exerciseID: String)
    /// Nothing is left to pick; the card shows "No available variation".
    case unavailable

    public var exerciseID: String? {
        switch self {
        case .variation(let id), .substitute(let id): id
        case .unavailable: nil
        }
    }

    public var isSubstitute: Bool {
        if case .substitute = self { true } else { false }
    }
}

/// Picks a concrete exercise for a movement slot (spec §7).
///
/// Holds the library and the user's state (hidden, liked, unavailable equipment, history) as plain
/// values. The stack engine mutates it as the workout goes: a down-swipe marks equipment unavailable,
/// "Never show" hides an exercise.
public struct VariationSelector: Equatable, Sendable {
    public private(set) var exercises: [String: SelectionExercise]
    public private(set) var movementTypes: [String: SelectionMovementType]
    /// Equipment ids unavailable at the current gym (see `EquipmentAvailability`).
    public var unavailableEquipment: Set<String>
    public var history: SelectionHistory
    public var tuning: SelectionTuning

    public init(
        exercises: [SelectionExercise],
        movementTypes: [SelectionMovementType],
        unavailableEquipment: Set<String> = [],
        history: SelectionHistory = .empty,
        tuning: SelectionTuning = .default
    ) {
        self.exercises = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.movementTypes = Dictionary(movementTypes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.unavailableEquipment = unavailableEquipment
        self.history = history
        self.tuning = tuning
    }

    public func exercise(_ id: String) -> SelectionExercise? { exercises[id] }

    // MARK: - User state changes

    public mutating func setHidden(_ exerciseID: String, _ hidden: Bool = true) {
        exercises[exerciseID]?.isHidden = hidden
    }

    public mutating func setLiked(_ exerciseID: String, _ liked: Bool = true) {
        exercises[exerciseID]?.isLiked = liked
    }

    public mutating func markUnavailable(_ equipment: Set<String>) {
        unavailableEquipment.formUnion(equipment)
    }

    // MARK: - Selection

    /// Picks an exercise for a slot of `movementType`, never one of `excluded` (the exercises
    /// already in today's stack). Falls back to a same-muscle substitute when the movement type has
    /// no candidates left, and to `.unavailable` when that pool is empty too.
    public func select(
        for movementType: String,
        excluding excluded: Set<String>,
        using rng: inout some RandomNumberGenerator
    ) -> SlotFill {
        let primary = weightedCandidates(for: movementType, excluding: excluded)
        if let id = Self.pick(primary, using: &rng) {
            return .variation(exerciseID: id)
        }
        let fallback = weightedSubstitutes(for: movementType, excluding: excluded)
        if let id = Self.pick(fallback, using: &rng) {
            return .substitute(exerciseID: id)
        }
        return .unavailable
    }

    /// The fill for a slot pinned to `exerciseID` in the split editor, or nil when the pin can't be
    /// honored today (the exercise is hidden, needs unavailable equipment, is already in the stack or
    /// no longer exists). The slot then goes through `select` like any other.
    public func pinnedFill(_ exerciseID: String, for movementType: String, excluding excluded: Set<String>) -> SlotFill? {
        guard let exercise = exercises[exerciseID], isEligible(exercise, excluded: excluded) else { return nil }
        return exercise.movementType == movementType
            ? .variation(exerciseID: exerciseID)
            : .substitute(exerciseID: exerciseID)
    }

    /// Eligible variations of a movement type with their weights, sorted by id.
    /// Also useful for a debug overlay.
    public func weightedCandidates(for movementType: String, excluding excluded: Set<String>) -> [(id: String, weight: Double)] {
        weighted(exercises.values.filter { $0.movementType == movementType && isEligible($0, excluded: excluded) })
    }

    /// Eligible exercises of other movement types that hit one of `movementType`'s primary muscles,
    /// with their weights, sorted by id.
    public func weightedSubstitutes(for movementType: String, excluding excluded: Set<String>) -> [(id: String, weight: Double)] {
        guard let muscles = movementTypes[movementType]?.primaryMuscles, !muscles.isEmpty else { return [] }
        return weighted(exercises.values.filter {
            $0.movementType != movementType && !$0.muscles.isDisjoint(with: muscles) && isEligible($0, excluded: excluded)
        })
    }

    /// The selection weight of an exercise, from likes and its own movement type's history.
    public func weight(of exercise: SelectionExercise) -> Double {
        var weight = 1.0
        if exercise.isLiked { weight *= tuning.likeBoost }
        let recent = history.recentWorkouts(of: exercise.movementType, limit: tuning.familiarityWindow)
        if recent.contains(where: { $0.contains(exercise.id) }) { weight *= tuning.familiarityBoost }
        if recent.first?.contains(exercise.id) == true { weight *= tuning.repeatDamping }
        return weight
    }

    private func isEligible(_ exercise: SelectionExercise, excluded: Set<String>) -> Bool {
        !exercise.isHidden
            && !excluded.contains(exercise.id)
            && exercise.equipment.isDisjoint(with: unavailableEquipment)
    }

    private func weighted(_ candidates: [SelectionExercise]) -> [(id: String, weight: Double)] {
        // Sorted so a seeded generator gives the same pick regardless of dictionary order.
        candidates.sorted { $0.id < $1.id }.map { ($0.id, weight(of: $0)) }
    }

    private static func pick(_ candidates: [(id: String, weight: Double)], using rng: inout some RandomNumberGenerator) -> String? {
        guard !candidates.isEmpty else { return nil }
        let total = candidates.reduce(0) { $0 + max($1.weight, 0) }
        guard total > 0 else { return candidates[Int.random(in: 0..<candidates.count, using: &rng)].id }
        var remaining = Double.random(in: 0..<total, using: &rng)
        for candidate in candidates {
            remaining -= max(candidate.weight, 0)
            if remaining < 0 { return candidate.id }
        }
        return candidates.last { $0.weight > 0 }?.id
    }
}
