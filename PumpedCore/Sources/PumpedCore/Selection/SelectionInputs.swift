/// An exercise as the selection algorithm sees it: the facts that affect whether and how often it's
/// picked. The app maps its SwiftData `Exercise` rows to these.
public struct SelectionExercise: Equatable, Codable, Sendable {
    public var id: String
    /// Movement type id.
    public var movementType: String
    /// Equipment ids. Empty for bodyweight exercises.
    public var equipment: Set<String>
    /// Muscle group ids.
    public var muscles: Set<String>
    /// "Never show me this".
    public var isHidden: Bool
    public var isLiked: Bool

    public init(
        id: String,
        movementType: String,
        equipment: Set<String> = [],
        muscles: Set<String> = [],
        isHidden: Bool = false,
        isLiked: Bool = false
    ) {
        self.id = id
        self.movementType = movementType
        self.equipment = equipment
        self.muscles = muscles
        self.isHidden = isHidden
        self.isLiked = isLiked
    }
}

public struct SelectionMovementType: Equatable, Codable, Sendable {
    public var id: String
    /// Muscle group ids. Exercises of other movement types that hit one of these are eligible
    /// substitutes when this movement type runs out of candidates.
    public var primaryMuscles: Set<String>

    public init(id: String, primaryMuscles: Set<String>) {
        self.id = id
        self.primaryMuscles = primaryMuscles
    }
}

/// Which exercises were done in past workouts, per movement type.
public struct SelectionHistory: Equatable, Codable, Sendable {
    /// For each movement type id, the exercise ids done in each past workout that trained it,
    /// most recent workout first.
    public var workoutsByMovementType: [String: [Set<String>]]

    public init(workoutsByMovementType: [String: [Set<String>]] = [:]) {
        self.workoutsByMovementType = workoutsByMovementType
    }

    public static let empty = SelectionHistory()

    /// The exercise id sets of the most recent `limit` workouts of a movement type, newest first.
    public func recentWorkouts(of movementType: String, limit: Int) -> ArraySlice<Set<String>> {
        (workoutsByMovementType[movementType] ?? []).prefix(max(limit, 0))
    }
}

extension SelectionExercise {
    /// Maps a seed record. Hidden and liked flags live on the app's model, so they default to false.
    public init(_ seed: SeedExercise, isHidden: Bool = false, isLiked: Bool = false) {
        self.init(
            id: seed.id,
            movementType: seed.movementType,
            equipment: Set(seed.equipment),
            muscles: Set(seed.muscles),
            isHidden: isHidden,
            isLiked: isLiked
        )
    }
}

extension SelectionMovementType {
    public init(_ seed: SeedMovementType) {
        self.init(id: seed.id, primaryMuscles: Set(seed.primaryMuscles))
    }
}

extension SelectionHistory {
    /// Builds the history from past workouts, newest first. Each workout maps a movement type id to
    /// the exercise ids done for it in that workout.
    public init(newestFirst workouts: [[String: Set<String>]]) {
        var byMovementType: [String: [Set<String>]] = [:]
        for workout in workouts {
            for (movementType, exerciseIDs) in workout where !exerciseIDs.isEmpty {
                byMovementType[movementType, default: []].append(exerciseIDs)
            }
        }
        self.init(workoutsByMovementType: byMovementType)
    }
}
