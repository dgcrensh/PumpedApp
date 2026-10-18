import Foundation

/// The bundled exercise library (`seed.json`), decoded as plain value types.
///
/// Every record carries a stable string `id`. The app imports records by `id`, so a later
/// seed with a higher `version` updates existing rows instead of duplicating them.
public struct SeedLibrary: Codable, Equatable, Sendable {
    public var version: Int
    public var muscleGroups: [SeedMuscleGroup]
    public var equipment: [SeedEquipment]
    public var movementTypes: [SeedMovementType]
    public var exercises: [SeedExercise]
    public var cardioOptions: [SeedCardioOption]
    public var stretches: [SeedStretch]
    public var stretchSequences: [SeedStretchSequence]

    public init(
        version: Int,
        muscleGroups: [SeedMuscleGroup] = [],
        equipment: [SeedEquipment] = [],
        movementTypes: [SeedMovementType] = [],
        exercises: [SeedExercise] = [],
        cardioOptions: [SeedCardioOption] = [],
        stretches: [SeedStretch] = [],
        stretchSequences: [SeedStretchSequence] = []
    ) {
        self.version = version
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.movementTypes = movementTypes
        self.exercises = exercises
        self.cardioOptions = cardioOptions
        self.stretches = stretches
        self.stretchSequences = stretchSequences
    }

    /// Decodes a seed file without validating it.
    public static func decode(from data: Data) throws -> SeedLibrary {
        try JSONDecoder().decode(SeedLibrary.self, from: data)
    }

    /// Decodes and validates a seed file, throwing `SeedValidationError` if it's inconsistent.
    public static func load(from data: Data) throws -> SeedLibrary {
        let library = try decode(from: data)
        try library.validate()
        return library
    }
}

public struct SeedMuscleGroup: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct SeedEquipment: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct SeedMovementType: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Muscle group ids. Used for the substitute fallback (spec §7).
    public var primaryMuscles: [String]

    public init(id: String, name: String, primaryMuscles: [String]) {
        self.id = id
        self.name = name
        self.primaryMuscles = primaryMuscles
    }
}

public struct SeedExercise: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// Movement type id.
    public var movementType: String
    /// Equipment ids. Empty for bodyweight exercises.
    public var equipment: [String]
    public var exerciseType: ExerciseType
    /// Muscle group ids.
    public var muscles: [String]

    public init(
        id: String,
        name: String,
        movementType: String,
        equipment: [String],
        exerciseType: ExerciseType,
        muscles: [String]
    ) {
        self.id = id
        self.name = name
        self.movementType = movementType
        self.equipment = equipment
        self.exerciseType = exerciseType
        self.muscles = muscles
    }
}

public struct SeedCardioOption: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct SeedStretch: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var defaultDurationSec: Int

    public init(id: String, name: String, defaultDurationSec: Int) {
        self.id = id
        self.name = name
        self.defaultDurationSec = defaultDurationSec
    }
}

public struct SeedStretchSequence: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var items: [Item]

    public struct Item: Codable, Equatable, Sendable {
        /// Stretch id.
        public var stretch: String
        public var durationSec: Int

        public init(stretch: String, durationSec: Int) {
            self.stretch = stretch
            self.durationSec = durationSec
        }
    }

    public init(id: String, name: String, items: [Item]) {
        self.id = id
        self.name = name
        self.items = items
    }
}
