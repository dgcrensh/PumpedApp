import Foundation
import OSLog
import PumpedCore
import SwiftData

/// What a card action did.
enum CardActionResult: Equatable {
    case applied
    /// Nothing to act on: wrong phase, no current card, or an empty slot.
    case ignored
    /// The card already has sets logged today, so its exercise can't be replaced.
    case hasSets
}

/// Enough to put the stack back the way it was before a swipe.
struct SwipeUndo {
    let direction: SwipeDirection
    let stack: WorkoutStack
    /// Exercise an up-swipe liked that wasn't liked before.
    let likedExerciseID: String?
}

/// The active workout's actions (spec §6), kept out of the views so they can be unit tested.
///
/// The persisted `WorkoutSession` is the source of truth. Each action rebuilds the `WorkoutStack`
/// from it, applies the change through `PumpedCore` and writes the result straight back, then saves,
/// so a force-quit at any point resumes where it left off.
@MainActor
enum WorkoutFlow {
    private static let logger = Logger(subsystem: "com.dgcrensh.pumped", category: "Workout")

    // MARK: Finding

    /// The unfinished workout, if any.
    static func activeSession(in context: ModelContext) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Finished workouts, newest first.
    static func finishedSessions(in context: ModelContext) -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Starting

    /// Starts a workout of `day`: fills every slot and begins in the warmup.
    @discardableResult
    static func start(
        day: SplitDay,
        of split: Split?,
        gym: Gym?,
        at now: Date = .now,
        in context: ModelContext,
        using rng: inout some RandomNumberGenerator
    ) -> WorkoutSession {
        let selector = makeSelector(gym: gym, now: now, in: context)
        let slots = day.orderedSlots.compactMap { $0.movementType?.id }
        let stack = WorkoutStack.build(slots: slots, selector: selector, using: &rng)
        let session = WorkoutSession(startedAt: now, split: split, splitDay: day, gym: gym)
        context.insert(session)
        write(stack, to: session, in: context)
        save(context)
        return session
    }

    /// The warmup cardio to preselect: the split day's default, else the last one logged.
    static func suggestedCardio(for session: WorkoutSession, in context: ModelContext) -> CardioOption? {
        if let cardio = session.splitDay?.defaultCardio { return cardio }
        return finishedSessions(in: context).lazy.compactMap { $0.warmup?.cardio }.first
    }

    // MARK: Warmup

    static func logWarmup(
        cardio: CardioOption?,
        durationSec: Int,
        distanceMi: Double?,
        in session: WorkoutSession,
        context: ModelContext
    ) {
        guard session.phase == .warmup, durationSec > 0 else { return }
        let log = WarmupLog(cardio: cardio, durationSec: durationSec, distanceMi: distanceMi)
        context.insert(log)
        session.warmup = log
        startLifting(session, in: context)
    }

    static func skipWarmup(_ session: WorkoutSession, in context: ModelContext) {
        startLifting(session, in: context)
    }

    private static func startLifting(_ session: WorkoutSession, in context: ModelContext) {
        var stack = Self.stack(of: session)
        guard stack.startLifting() else { return }
        write(stack, to: session, in: context)
        save(context)
    }

    // MARK: Lifting

    /// The row behind the top card.
    static func currentEntry(of session: WorkoutSession) -> WorkoutEntry? {
        guard let id = Self.stack(of: session).current?.id else { return nil }
        return session.entries.first { $0.slotOrder == id }
    }

    /// Logs a set and starts the rest timer for the exercise's type (spec §6.2).
    @discardableResult
    static func logSet(
        _ values: SetValues,
        on entry: WorkoutEntry,
        at now: Date = .now,
        in context: ModelContext
    ) -> SetLog {
        let set = SetLog(reps: values.reps, weightLb: values.weightLb, loggedAt: now)
        context.insert(set)
        entry.sets.append(set)
        if let session = entry.session {
            var timer = restTimer(of: session)
            timer.start(seconds: restSeconds(for: entry.exercise, in: context), at: now)
            session.restTimerEndsAt = timer.endsAt
        }
        save(context)
        return set
    }

    static func deleteSet(_ set: SetLog, in context: ModelContext) {
        set.entry?.sets.removeAll { $0 === set }
        context.delete(set)
        save(context)
    }

    // MARK: Rest timer

    static func restTimer(of session: WorkoutSession) -> RestTimer {
        RestTimer(endsAt: session.restTimerEndsAt)
    }

    /// The rest after a set of `exercise`, from Settings. Compound when the card is empty.
    static func restSeconds(for exercise: Exercise?, in context: ModelContext) -> Int {
        restTimerSettings(in: context).seconds(for: exercise?.exerciseType ?? .compound)
    }

    /// The settings row, created with the defaults if it's missing.
    static func restTimerSettings(in context: ModelContext) -> RestTimerSettings {
        if let settings = try? context.fetch(FetchDescriptor<RestTimerSettings>()).first { return settings }
        let settings = RestTimerSettings()
        context.insert(settings)
        return settings
    }

    static func skipRest(in session: WorkoutSession, context: ModelContext) {
        session.restTimerEndsAt = nil
        save(context)
    }

    /// "+30s".
    static func extendRest(in session: WorkoutSession, at now: Date = .now, context: ModelContext) {
        var timer = restTimer(of: session)
        timer.extend(at: now)
        session.restTimerEndsAt = timer.endsAt
        save(context)
    }

    /// Applies a swipe to the top card. Right, left and up return an undo; down doesn't, because it
    /// also changes what's stored for the gym.
    static func swipe(
        _ direction: SwipeDirection,
        in session: WorkoutSession,
        at now: Date = .now,
        context: ModelContext,
        using rng: inout some RandomNumberGenerator
    ) -> (result: CardActionResult, undo: SwipeUndo?) {
        var stack = Self.stack(of: session)
        guard let current = stack.current else { return (.ignored, nil) }
        let before = stack

        switch direction {
        case .right:
            stack.swipeRight()
        case .left:
            stack.swipeLeft()
        case .up:
            var selector = makeSelector(gym: session.gym, excluding: session, now: now, in: context)
            guard let id = stack.swipeUp(selector: &selector), let exercise = Self.exercise(id, in: context) else {
                return (.ignored, nil)
            }
            let wasLiked = exercise.isLiked
            exercise.isLiked = true
            save(context)
            return (.applied, SwipeUndo(direction: .up, stack: before, likedExerciseID: wasLiked ? nil : id))
        case .down:
            guard current.exerciseID != nil else { return (.ignored, nil) }
            if hasSets(current, in: session) { return (.hasSets, nil) }
            var selector = makeSelector(gym: session.gym, excluding: session, now: now, in: context)
            guard let equipment = stack.swipeDown(selector: &selector, using: &rng) else { return (.ignored, nil) }
            markUnavailable(equipment, at: session.gym, on: now, in: context)
            write(stack, to: session, in: context)
            save(context)
            return (.applied, nil)
        }

        write(stack, to: session, in: context)
        save(context)
        return (.applied, SwipeUndo(direction: direction, stack: before, likedExerciseID: nil))
    }

    /// Puts the stack back as it was before the swipe, and takes back a like the swipe added.
    static func undo(_ undo: SwipeUndo, in session: WorkoutSession, context: ModelContext) {
        guard session.endedAt == nil else { return }
        write(undo.stack, to: session, in: context)
        if let id = undo.likedExerciseID { exercise(id, in: context)?.isLiked = false }
        save(context)
    }

    // MARK: Card menu and extra slots

    /// "Swap variation": puts a manually picked exercise on the top card.
    static func swapCurrent(to exerciseID: String, in session: WorkoutSession, context: ModelContext) -> CardActionResult {
        var stack = Self.stack(of: session)
        guard let current = stack.current else { return .ignored }
        if hasSets(current, in: session) { return .hasSets }
        let selector = makeSelector(gym: session.gym, excluding: session, now: .now, in: context)
        guard stack.swapCurrent(to: exerciseID, selector: selector) else { return .ignored }
        write(stack, to: session, in: context)
        save(context)
        return .applied
    }

    /// "Never show me this": hides the top card's exercise and refills its slot.
    static func hideCurrent(
        in session: WorkoutSession,
        context: ModelContext,
        using rng: inout some RandomNumberGenerator
    ) -> CardActionResult {
        var stack = Self.stack(of: session)
        guard let current = stack.current else { return .ignored }
        if hasSets(current, in: session) { return .hasSets }
        var selector = makeSelector(gym: session.gym, excluding: session, now: .now, in: context)
        guard let id = stack.hideCurrent(selector: &selector, using: &rng) else { return .ignored }
        exercise(id, in: context)?.isHidden = true
        write(stack, to: session, in: context)
        save(context)
        return .applied
    }

    static func setLiked(_ exercise: Exercise, _ liked: Bool, in context: ModelContext) {
        exercise.isLiked = liked
        save(context)
    }

    /// "Add exercise": a new slot behind the remaining cards.
    @discardableResult
    static func addExercise(
        movementTypeID: String,
        to session: WorkoutSession,
        context: ModelContext,
        using rng: inout some RandomNumberGenerator
    ) -> Bool {
        var stack = Self.stack(of: session)
        let selector = makeSelector(gym: session.gym, excluding: session, now: .now, in: context)
        guard stack.addSlot(movementTypeID, selector: selector, using: &rng) != nil else { return false }
        write(stack, to: session, in: context)
        save(context)
        return true
    }

    /// Exercises the top card can be swapped to: anything not hidden and not elsewhere in the stack.
    static func swapCandidates(for session: WorkoutSession, in context: ModelContext) -> [Exercise] {
        let stack = Self.stack(of: session)
        let taken = stack.exerciseIDsInStack.subtracting([stack.current?.exerciseID].compactMap { $0 })
        let all = (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
        return all.filter { !$0.isHidden && !taken.contains($0.id) }
    }

    // MARK: Finishing

    /// "Finish lifting": unfinished cards stay pending and the workout moves to the cool-down.
    static func finishLifting(_ session: WorkoutSession, in context: ModelContext) {
        var stack = Self.stack(of: session)
        stack.startLifting()
        guard stack.finishLifting() else { return }
        write(stack, to: session, in: context)
        session.restTimerEndsAt = nil
        save(context)
    }

    /// Completes the workout. The split moves past the day just trained, but only when at least one
    /// lifting set was logged (spec §6.4).
    static func finish(
        _ session: WorkoutSession,
        cooldownCompleted: Bool,
        at now: Date = .now,
        in context: ModelContext
    ) {
        guard session.endedAt == nil else { return }
        var stack = Self.stack(of: session)
        stack.startLifting()
        stack.finishLifting()
        stack.finishCooldown()
        write(stack, to: session, in: context)
        session.endedAt = now
        session.cooldownCompleted = cooldownCompleted
        session.restTimerEndsAt = nil
        if hasLoggedSets(session), let split = session.split {
            advance(split, past: session.splitDay)
        }
        save(context)
    }

    /// Throws the workout away, e.g. after starting one by accident. The split doesn't move.
    static func discard(_ session: WorkoutSession, in context: ModelContext) {
        context.delete(session)
        save(context)
    }

    static func hasLoggedSets(_ session: WorkoutSession) -> Bool {
        session.entries.contains { !$0.sets.isEmpty }
    }

    // MARK: History

    /// The sets from the most recent finished workout before `session` that included the exercise.
    static func lastSets(
        of exerciseID: String,
        before session: WorkoutSession?,
        in context: ModelContext
    ) -> (date: Date, sets: [SetValues])? {
        for past in finishedSessions(in: context) where past !== session {
            if let session, past.startedAt >= session.startedAt { continue }
            let sets = past.entries.filter { $0.exercise?.id == exerciseID }.flatMap(\.orderedSets)
            if !sets.isEmpty { return (past.startedAt, sets.map(values)) }
        }
        return nil
    }

    /// Every set of the exercise from finished workouts that started before `session`.
    static func allSets(of exerciseID: String, before session: WorkoutSession, in context: ModelContext) -> [SetValues] {
        finishedSessions(in: context)
            .filter { $0 !== session && $0.startedAt < session.startedAt }
            .flatMap { $0.entries.filter { $0.exercise?.id == exerciseID }.flatMap(\.orderedSets) }
            .map(values)
    }

    /// The end-of-workout numbers (spec §6.4), with PRs measured against earlier workouts.
    static func summary(of session: WorkoutSession, in context: ModelContext) -> WorkoutSummary {
        let exercises = session.entries
            .sorted { $0.slotOrder < $1.slotOrder }
            .compactMap { entry -> WorkoutSummary.Exercise? in
                guard let exercise = entry.exercise else { return nil }
                return WorkoutSummary.Exercise(
                    name: exercise.name,
                    sets: entry.orderedSets.map(values),
                    history: allSets(of: exercise.id, before: session, in: context)
                )
            }
        return WorkoutSummary(startedAt: session.startedAt, endedAt: session.endedAt ?? .now, exercises: exercises)
    }

    static func values(_ set: SetLog) -> SetValues {
        SetValues(reps: set.reps, weightLb: set.weightLb)
    }

    // MARK: Stack ⇄ SwiftData

    /// Rebuilds the core stack from the session's rows.
    static func stack(of session: WorkoutSession) -> WorkoutStack {
        let rows = session.entries.sorted { $0.slotOrder < $1.slotOrder }
        let entries = rows.map { row in
            StackEntry(
                id: row.slotOrder,
                movementType: row.movementTypeID ?? row.exercise?.movementType?.id ?? "",
                fill: fill(of: row),
                status: row.status
            )
        }
        let queue = rows
            .filter { $0.status == .pending }
            .sorted { ($0.stackPosition, $0.slotOrder) < ($1.stackPosition, $1.slotOrder) }
            .map(\.slotOrder)
        return WorkoutStack(phase: session.phase, entries: entries, queue: queue)
    }

    /// Writes the core stack back to the session's rows, adding rows for new slots.
    static func write(_ stack: WorkoutStack, to session: WorkoutSession, in context: ModelContext) {
        var rows = Dictionary(session.entries.map { ($0.slotOrder, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in stack.entries {
            let row: WorkoutEntry
            if let existing = rows[entry.id] {
                row = existing
            } else {
                row = WorkoutEntry(slotOrder: entry.id, exercise: nil, stackPosition: 0)
                context.insert(row)
                session.entries.append(row)
                rows[entry.id] = row
            }
            if row.exercise?.id != entry.exerciseID {
                row.exercise = entry.exerciseID.flatMap { exercise($0, in: context) }
            }
            row.movementTypeID = entry.movementType
            row.isSubstitute = entry.fill.isSubstitute
            row.status = entry.status
            row.stackPosition = stack.stackPosition(of: entry.id) ?? -1
        }
        session.phase = stack.phase
    }

    private static func fill(of row: WorkoutEntry) -> SlotFill {
        guard let id = row.exercise?.id else { return .unavailable }
        return row.isSubstitute ? .substitute(exerciseID: id) : .variation(exerciseID: id)
    }

    // MARK: Selection inputs

    /// The selector over the whole library, with the gym's unavailable equipment and past workouts.
    static func makeSelector(
        gym: Gym?,
        excluding current: WorkoutSession? = nil,
        now: Date,
        in context: ModelContext
    ) -> VariationSelector {
        let exercises = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map(selectionExercise)
        let movementTypes = ((try? context.fetch(FetchDescriptor<MovementType>())) ?? []).map {
            SelectionMovementType(id: $0.id, primaryMuscles: Set($0.primaryMuscles))
        }
        return VariationSelector(
            exercises: exercises,
            movementTypes: movementTypes,
            unavailableEquipment: unavailableEquipment(at: gym, now: now),
            history: history(excluding: current, in: context)
        )
    }

    static func selectionExercise(_ exercise: Exercise) -> SelectionExercise {
        SelectionExercise(
            id: exercise.id,
            movementType: exercise.movementType?.id ?? "",
            equipment: Set(exercise.equipment.map(\.id)),
            muscles: Set(exercise.muscles),
            isHidden: exercise.isHidden,
            isLiked: exercise.isLiked
        )
    }

    static func unavailableEquipment(at gym: Gym?, now: Date) -> Set<String> {
        guard let gym else { return [] }
        let marks = gym.unavailableEquipment.compactMap { row in
            row.equipment.map { EquipmentAvailability.Mark(gymID: gym.id, equipmentID: $0.id, markedAt: row.markedAt) }
        }
        return EquipmentAvailability(marks: marks).unavailableEquipment(at: gym.id, now: now)
    }

    /// Which exercises each finished workout trained, per movement type, newest first. Only cards
    /// with logged sets count.
    static func history(excluding current: WorkoutSession?, in context: ModelContext) -> SelectionHistory {
        let workouts = finishedSessions(in: context).filter { $0 !== current }.map { session in
            var done: [String: Set<String>] = [:]
            for entry in session.entries where !entry.sets.isEmpty {
                guard let exercise = entry.exercise, let movementType = exercise.movementType?.id else { continue }
                done[movementType, default: []].insert(exercise.id)
            }
            return done
        }
        return SelectionHistory(newestFirst: workouts)
    }

    // MARK: Helpers

    /// Records a down-swipe at the gym, restarting the 7 days for equipment already marked. With no
    /// gym there's nothing to remember.
    private static func markUnavailable(_ equipmentIDs: Set<String>, at gym: Gym?, on now: Date, in context: ModelContext) {
        guard let gym else { return }
        for id in equipmentIDs.sorted() {
            if let row = gym.unavailableEquipment.first(where: { $0.equipment?.id == id }) {
                row.markedAt = now
            } else if let equipment = try? context.fetch(FetchDescriptor<Equipment>(predicate: #Predicate { $0.id == id })).first {
                let row = EquipmentUnavailability(gym: nil, equipment: equipment, markedAt: now)
                context.insert(row)
                gym.unavailableEquipment.append(row)
            }
        }
    }

    private static func advance(_ split: Split, past day: SplitDay?) {
        let days = split.orderedDays
        // If the day was deleted mid-workout, the cycle already points past it.
        guard let index = days.firstIndex(where: { $0 === day }) else { return }
        split.nextDayIndex = SplitCycle(dayCount: days.count, nextDayIndex: index).advanced().nextDayIndex
    }

    private static func hasSets(_ entry: StackEntry, in session: WorkoutSession) -> Bool {
        session.entries.first { $0.slotOrder == entry.id }?.sets.isEmpty == false
    }

    private static func exercise(_ id: String, in context: ModelContext) -> Exercise? {
        try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            logger.error("Saving the workout failed: \(String(describing: error), privacy: .public)")
            assertionFailure("Saving the workout failed: \(error)")
        }
    }
}
