import Foundation
import PumpedCore
import SwiftData

/// Version 1 of the persisted model (spec §11).
///
/// Later model changes add a `PumpedSchemaV2` and a migration stage in `PumpedMigrationPlan`
/// rather than editing these types, so existing history survives app updates.
enum PumpedSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            MovementType.self,
            Exercise.self,
            Equipment.self,
            CardioOption.self,
            Stretch.self,
            StretchSequence.self,
            StretchItem.self,
            Split.self,
            SplitDay.self,
            MovementSlot.self,
            Gym.self,
            EquipmentUnavailability.self,
            WorkoutSession.self,
            WarmupLog.self,
            WorkoutEntry.self,
            SetLog.self,
            RestTimerSettings.self,
            SeedState.self,
        ]
    }

    // MARK: Library

    @Model
    final class MovementType {
        /// Stable id; matches `seed.json` for library rows.
        @Attribute(.unique) var id: String
        var name: String
        /// Muscle group ids from the seed library.
        var primaryMuscles: [String]
        @Relationship(inverse: \Exercise.movementType)
        var exercises: [Exercise] = []

        init(id: String, name: String, primaryMuscles: [String] = []) {
            self.id = id
            self.name = name
            self.primaryMuscles = primaryMuscles
        }
    }

    @Model
    final class Exercise {
        @Attribute(.unique) var id: String
        var name: String
        var movementType: MovementType?
        var equipment: [Equipment] = []
        var exerciseTypeRaw: String
        /// Muscle group ids from the seed library.
        var muscles: [String]
        var isCustom: Bool
        var isHidden: Bool
        var isLiked: Bool

        var exerciseType: ExerciseType {
            get { ExerciseType(rawValue: exerciseTypeRaw) ?? .compound }
            set { exerciseTypeRaw = newValue.rawValue }
        }

        init(
            id: String = UUID().uuidString,
            name: String,
            movementType: MovementType? = nil,
            exerciseType: ExerciseType,
            muscles: [String] = [],
            isCustom: Bool = false,
            isHidden: Bool = false,
            isLiked: Bool = false
        ) {
            self.id = id
            self.name = name
            self.movementType = movementType
            self.exerciseTypeRaw = exerciseType.rawValue
            self.muscles = muscles
            self.isCustom = isCustom
            self.isHidden = isHidden
            self.isLiked = isLiked
        }
    }

    @Model
    final class Equipment {
        @Attribute(.unique) var id: String
        var name: String
        @Relationship(inverse: \Exercise.equipment)
        var exercises: [Exercise] = []

        init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    @Model
    final class CardioOption {
        @Attribute(.unique) var id: String
        var name: String

        init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    @Model
    final class Stretch {
        @Attribute(.unique) var id: String
        var name: String
        var defaultDurationSec: Int
        var isCustom: Bool

        init(id: String = UUID().uuidString, name: String, defaultDurationSec: Int, isCustom: Bool = false) {
            self.id = id
            self.name = name
            self.defaultDurationSec = defaultDurationSec
            self.isCustom = isCustom
        }
    }

    @Model
    final class StretchSequence {
        @Attribute(.unique) var id: String
        var name: String
        /// Default sequences come from the seed and are read-only in the editor.
        var isDefault: Bool
        @Relationship(deleteRule: .cascade, inverse: \StretchItem.sequence)
        var items: [StretchItem] = []

        var orderedItems: [StretchItem] { items.sorted { $0.order < $1.order } }

        init(id: String = UUID().uuidString, name: String, isDefault: Bool = false) {
            self.id = id
            self.name = name
            self.isDefault = isDefault
        }
    }

    @Model
    final class StretchItem {
        var stretch: Stretch?
        var durationSec: Int
        var order: Int
        var sequence: StretchSequence?

        init(stretch: Stretch?, durationSec: Int, order: Int) {
            self.stretch = stretch
            self.durationSec = durationSec
            self.order = order
        }
    }

    // MARK: Splits

    @Model
    final class Split {
        @Attribute(.unique) var id: String
        var name: String
        var isActive: Bool
        /// Index into `orderedDays` of the day the next workout uses.
        var nextDayIndex: Int
        var createdAt: Date
        @Relationship(deleteRule: .cascade, inverse: \SplitDay.split)
        var days: [SplitDay] = []

        var orderedDays: [SplitDay] { days.sorted { $0.order < $1.order } }

        init(id: String = UUID().uuidString, name: String, isActive: Bool = false, nextDayIndex: Int = 0, createdAt: Date = .now) {
            self.id = id
            self.name = name
            self.isActive = isActive
            self.nextDayIndex = nextDayIndex
            self.createdAt = createdAt
        }
    }

    @Model
    final class SplitDay {
        @Attribute(.unique) var id: String
        var name: String
        var order: Int
        var split: Split?
        @Relationship(deleteRule: .cascade, inverse: \MovementSlot.splitDay)
        var slots: [MovementSlot] = []
        var stretchSequence: StretchSequence?
        var defaultCardio: CardioOption?

        var orderedSlots: [MovementSlot] { slots.sorted { $0.order < $1.order } }

        init(id: String = UUID().uuidString, name: String, order: Int) {
            self.id = id
            self.name = name
            self.order = order
        }
    }

    @Model
    final class MovementSlot {
        var movementType: MovementType?
        var order: Int
        var splitDay: SplitDay?

        init(movementType: MovementType?, order: Int) {
            self.movementType = movementType
            self.order = order
        }
    }

    // MARK: Gyms

    @Model
    final class Gym {
        @Attribute(.unique) var id: String
        var name: String
        var latitude: Double
        var longitude: Double
        /// Match radius in meters (spec §8).
        var radius: Double
        @Relationship(deleteRule: .cascade, inverse: \EquipmentUnavailability.gym)
        var unavailableEquipment: [EquipmentUnavailability] = []

        init(id: String = UUID().uuidString, name: String, latitude: Double, longitude: Double, radius: Double = 150) {
            self.id = id
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.radius = radius
        }
    }

    @Model
    final class EquipmentUnavailability {
        var gym: Gym?
        var equipment: Equipment?
        /// Last down-swipe; the equipment is excluded for 7 days from this date.
        var markedAt: Date

        init(gym: Gym?, equipment: Equipment?, markedAt: Date = .now) {
            self.gym = gym
            self.equipment = equipment
            self.markedAt = markedAt
        }
    }

    // MARK: Workouts

    @Model
    final class WorkoutSession {
        @Attribute(.unique) var id: String
        var startedAt: Date
        var endedAt: Date?
        var split: Split?
        var splitDay: SplitDay?
        var gym: Gym?
        var phaseRaw: String
        @Relationship(deleteRule: .cascade, inverse: \WarmupLog.session)
        var warmup: WarmupLog?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.session)
        var entries: [WorkoutEntry] = []
        var cooldownCompleted: Bool
        /// Absolute end of the running rest timer, so it survives backgrounding and termination.
        var restTimerEndsAt: Date?

        var phase: WorkoutPhase {
            get { WorkoutPhase(rawValue: phaseRaw) ?? .warmup }
            set { phaseRaw = newValue.rawValue }
        }

        /// Cards in their current stack order.
        var stack: [WorkoutEntry] { entries.sorted { $0.stackPosition < $1.stackPosition } }

        init(
            id: String = UUID().uuidString,
            startedAt: Date = .now,
            split: Split? = nil,
            splitDay: SplitDay? = nil,
            gym: Gym? = nil,
            phase: WorkoutPhase = .warmup
        ) {
            self.id = id
            self.startedAt = startedAt
            self.split = split
            self.splitDay = splitDay
            self.gym = gym
            self.phaseRaw = phase.rawValue
            self.cooldownCompleted = false
        }
    }

    @Model
    final class WarmupLog {
        var cardio: CardioOption?
        var durationSec: Int
        var distanceMi: Double?
        var session: WorkoutSession?

        init(cardio: CardioOption?, durationSec: Int, distanceMi: Double? = nil) {
            self.cardio = cardio
            self.durationSec = durationSec
            self.distanceMi = distanceMi
        }
    }

    @Model
    final class WorkoutEntry {
        /// Position of the split-day slot this card fills (or after the last slot when added mid-workout).
        var slotOrder: Int
        var exercise: Exercise?
        var stackPosition: Int
        var statusRaw: String
        /// True when the variation came from the shared-muscle fallback (spec §7).
        var isSubstitute: Bool
        var session: WorkoutSession?
        @Relationship(deleteRule: .cascade, inverse: \SetLog.entry)
        var sets: [SetLog] = []

        var status: EntryStatus {
            get { EntryStatus(rawValue: statusRaw) ?? .pending }
            set { statusRaw = newValue.rawValue }
        }

        var orderedSets: [SetLog] { sets.sorted { $0.loggedAt < $1.loggedAt } }

        init(slotOrder: Int, exercise: Exercise?, stackPosition: Int, isSubstitute: Bool = false) {
            self.slotOrder = slotOrder
            self.exercise = exercise
            self.stackPosition = stackPosition
            self.statusRaw = EntryStatus.pending.rawValue
            self.isSubstitute = isSubstitute
        }
    }

    @Model
    final class SetLog {
        var reps: Int
        var weightLb: Double
        var loggedAt: Date
        var entry: WorkoutEntry?

        init(reps: Int, weightLb: Double, loggedAt: Date = .now) {
            self.reps = reps
            self.weightLb = weightLb
            self.loggedAt = loggedAt
        }
    }

    // MARK: Settings and bookkeeping

    /// Singleton row with per-exercise-type rest durations.
    @Model
    final class RestTimerSettings {
        var heavyCompoundSec: Int
        var compoundSec: Int
        var isolationSec: Int

        init(
            heavyCompoundSec: Int = ExerciseType.heavyCompound.defaultRestSeconds,
            compoundSec: Int = ExerciseType.compound.defaultRestSeconds,
            isolationSec: Int = ExerciseType.isolation.defaultRestSeconds
        ) {
            self.heavyCompoundSec = heavyCompoundSec
            self.compoundSec = compoundSec
            self.isolationSec = isolationSec
        }

        func seconds(for type: ExerciseType) -> Int {
            switch type {
            case .heavyCompound: heavyCompoundSec
            case .compound: compoundSec
            case .isolation: isolationSec
            }
        }
    }

    /// Singleton row recording which `seed.json` version has been imported into this store.
    @Model
    final class SeedState {
        var appliedVersion: Int

        init(appliedVersion: Int) {
            self.appliedVersion = appliedVersion
        }
    }
}
