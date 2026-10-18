import Foundation
import PumpedCore
import SwiftData

/// Version 2: workout cards remember their slot's movement type, so a stack can be rebuilt exactly
/// on resume even when a card holds a substitute or nothing at all (spec §6.4, §7).
///
/// Only the workout models changed. They're redeclared here because they point at each other;
/// library, split and gym models are reused from version 1.
enum PumpedSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            PumpedSchemaV1.MovementType.self,
            PumpedSchemaV1.Exercise.self,
            PumpedSchemaV1.Equipment.self,
            PumpedSchemaV1.CardioOption.self,
            PumpedSchemaV1.Stretch.self,
            PumpedSchemaV1.StretchSequence.self,
            PumpedSchemaV1.StretchItem.self,
            PumpedSchemaV1.Split.self,
            PumpedSchemaV1.SplitDay.self,
            PumpedSchemaV1.MovementSlot.self,
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

    @Model
    final class WorkoutSession {
        @Attribute(.unique) var id: String
        var startedAt: Date
        var endedAt: Date?
        var split: PumpedSchemaV1.Split?
        var splitDay: PumpedSchemaV1.SplitDay?
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
            split: PumpedSchemaV1.Split? = nil,
            splitDay: PumpedSchemaV1.SplitDay? = nil,
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
typealias Split = PumpedSchemaV1.Split
typealias SplitDay = PumpedSchemaV1.SplitDay
typealias MovementSlot = PumpedSchemaV1.MovementSlot
typealias Gym = PumpedSchemaV1.Gym
typealias EquipmentUnavailability = PumpedSchemaV1.EquipmentUnavailability
typealias WorkoutSession = PumpedSchemaV2.WorkoutSession
typealias WarmupLog = PumpedSchemaV2.WarmupLog
typealias WorkoutEntry = PumpedSchemaV2.WorkoutEntry
typealias SetLog = PumpedSchemaV2.SetLog
typealias RestTimerSettings = PumpedSchemaV1.RestTimerSettings
typealias SeedState = PumpedSchemaV1.SeedState
