import Foundation
import PumpedCore
import SwiftData

/// Version 3: a split day's movement slot can be pinned to one exercise, which workouts then use
/// instead of a weighted pick whenever it can be done.
///
/// Only `MovementSlot` changed. The split models that hold it and the workout models that point at
/// those are redeclared here because they point at each other; library and gym models are reused
/// from version 1.
enum PumpedSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            PumpedSchemaV1.MovementType.self,
            PumpedSchemaV1.Exercise.self,
            PumpedSchemaV1.Equipment.self,
            PumpedSchemaV1.CardioOption.self,
            PumpedSchemaV1.Stretch.self,
            PumpedSchemaV1.StretchSequence.self,
            PumpedSchemaV1.StretchItem.self,
            Split.self,
            SplitDay.self,
            MovementSlot.self,
            PumpedSchemaV1.Gym.self,
            PumpedSchemaV1.EquipmentUnavailability.self,
            WorkoutSession.self,
            WarmupLog.self,
            WorkoutEntry.self,
            SetLog.self,
            PumpedSchemaV1.RestTimerSettings.self,
            PumpedSchemaV1.SeedState.self,
        ]
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
        var stretchSequence: PumpedSchemaV1.StretchSequence?
        var defaultCardio: PumpedSchemaV1.CardioOption?

        var orderedSlots: [MovementSlot] { slots.sorted { $0.order < $1.order } }

        init(id: String = UUID().uuidString, name: String, order: Int) {
            self.id = id
            self.name = name
            self.order = order
        }
    }

    @Model
    final class MovementSlot {
        var movementType: PumpedSchemaV1.MovementType?
        var order: Int
        var splitDay: SplitDay?
        /// The exercise this slot always uses when it can (not hidden, equipment available at the
        /// gym). Nil lets the selection algorithm pick and rotate variations (spec §7).
        var pinnedExercise: PumpedSchemaV1.Exercise?

        init(movementType: PumpedSchemaV1.MovementType?, order: Int, pinnedExercise: PumpedSchemaV1.Exercise? = nil) {
            self.movementType = movementType
            self.order = order
            self.pinnedExercise = pinnedExercise
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
        var gym: PumpedSchemaV1.Gym?
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
            gym: PumpedSchemaV1.Gym? = nil,
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
        var cardio: PumpedSchemaV1.CardioOption?
        var durationSec: Int
        var distanceMi: Double?
        var session: WorkoutSession?

        init(cardio: PumpedSchemaV1.CardioOption?, durationSec: Int, distanceMi: Double? = nil) {
            self.cardio = cardio
            self.durationSec = durationSec
            self.distanceMi = distanceMi
        }
    }

    @Model
    final class WorkoutEntry {
        /// The card's id in the workout's `WorkoutStack`: the split-day slot it fills (0..<n), or
        /// after the last slot when added mid-workout.
        var slotOrder: Int
        /// The slot's movement type id. Nil only for cards saved before version 2.
        var movementTypeID: String?
        var exercise: PumpedSchemaV1.Exercise?
        /// Position among pending cards (0 = on top). -1 once the card is done.
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

        init(
            slotOrder: Int,
            movementTypeID: String? = nil,
            exercise: PumpedSchemaV1.Exercise?,
            stackPosition: Int,
            isSubstitute: Bool = false
        ) {
            self.slotOrder = slotOrder
            self.movementTypeID = movementTypeID
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
}

// The rest of the app always uses the current schema's types.
typealias MovementType = PumpedSchemaV1.MovementType
typealias Exercise = PumpedSchemaV1.Exercise
typealias Equipment = PumpedSchemaV1.Equipment
typealias CardioOption = PumpedSchemaV1.CardioOption
typealias Stretch = PumpedSchemaV1.Stretch
typealias StretchSequence = PumpedSchemaV1.StretchSequence
typealias StretchItem = PumpedSchemaV1.StretchItem
typealias Split = PumpedSchemaV3.Split
typealias SplitDay = PumpedSchemaV3.SplitDay
typealias MovementSlot = PumpedSchemaV3.MovementSlot
typealias Gym = PumpedSchemaV1.Gym
typealias EquipmentUnavailability = PumpedSchemaV1.EquipmentUnavailability
typealias WorkoutSession = PumpedSchemaV3.WorkoutSession
typealias WarmupLog = PumpedSchemaV3.WarmupLog
typealias WorkoutEntry = PumpedSchemaV3.WorkoutEntry
typealias SetLog = PumpedSchemaV3.SetLog
typealias RestTimerSettings = PumpedSchemaV1.RestTimerSettings
typealias SeedState = PumpedSchemaV1.SeedState
