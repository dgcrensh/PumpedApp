/// One card in the lifting stack: a movement slot and the exercise filling it.
public struct StackEntry: Equatable, Codable, Sendable, Identifiable {
    /// Unique within the workout. Equals the slot's order: split day slots are 0..<n, slots added
    /// mid-workout continue from there.
    public var id: Int
    /// The slot's movement type id.
    public var movementType: String
    public var fill: SlotFill
    public var status: EntryStatus

    public init(id: Int, movementType: String, fill: SlotFill, status: EntryStatus = .pending) {
        self.id = id
        self.movementType = movementType
        self.fill = fill
        self.status = status
    }

    public var exerciseID: String? { fill.exerciseID }
}

/// The workout's state machine (spec §6): phases, the lifting stack and what each swipe does.
///
/// A plain value, so the app can persist it after every change and resume after termination. Card
/// order is enforced: cards come in slot order, and only a left swipe or an added slot changes
/// where a card sits. Actions that don't apply in the current phase (or with no current card) do
/// nothing and return nil or false.
public struct WorkoutStack: Equatable, Codable, Sendable {
    public private(set) var phase: WorkoutPhase
    /// Every entry ever in the stack, in slot order, including finished ones.
    public private(set) var entries: [StackEntry]
    /// Ids of pending entries in the order they'll be shown. The first is the current card.
    public private(set) var queue: [Int]

    /// Restores a persisted stack. Use `build` to start a new one.
    public init(phase: WorkoutPhase, entries: [StackEntry], queue: [Int]) {
        self.phase = phase
        self.entries = entries
        self.queue = queue
    }

    /// Fills every slot of a split day, in order, so duplicate movement types get distinct exercises.
    /// Starts in the warmup phase.
    public static func build(
        slots movementTypes: [String],
        selector: VariationSelector,
        using rng: inout some RandomNumberGenerator
    ) -> WorkoutStack {
        var stack = WorkoutStack(phase: .warmup, entries: [], queue: [])
        for movementType in movementTypes {
            stack.append(movementType, selector: selector, using: &rng)
        }
        return stack
    }

    // MARK: - Reading

    public var current: StackEntry? {
        guard phase == .lifting, let id = queue.first else { return nil }
        return entry(id)
    }

    public func entry(_ id: Int) -> StackEntry? {
        entries.first { $0.id == id }
    }

    /// Pending entries in the order they'll be shown.
    public var pending: [StackEntry] {
        queue.compactMap(entry)
    }

    /// Position in the stack (0 = current) of a pending entry, for persisting `stackPosition`.
    public func stackPosition(of id: Int) -> Int? {
        queue.firstIndex(of: id)
    }

    /// Exercises already in today's stack, done or pending. Never picked again for another slot.
    public var exerciseIDsInStack: Set<String> {
        Set(entries.compactMap(\.exerciseID))
    }

    // MARK: - Phases

    /// Logging or skipping the warmup starts lifting. An empty stack goes straight to cool-down.
    @discardableResult
    public mutating func startLifting() -> Bool {
        guard phase == .warmup else { return false }
        phase = queue.isEmpty ? .cooldown : .lifting
        return true
    }

    /// "Finish lifting": available at any time during lifting. Unfinished cards stay pending.
    @discardableResult
    public mutating func finishLifting() -> Bool {
        guard phase == .lifting else { return false }
        phase = .cooldown
        return true
    }

    /// Finishing or skipping the cool-down completes the workout.
    @discardableResult
    public mutating func finishCooldown() -> Bool {
        guard phase == .cooldown else { return false }
        phase = .complete
        return true
    }

    // MARK: - Swipes

    /// → Right: done with the current exercise. Moves to cool-down once nothing is pending.
    /// Returns the finished entry.
    @discardableResult
    public mutating func swipeRight() -> StackEntry? {
        guard var entry = current else { return nil }
        entry.status = .done
        replace(entry)
        queue.removeFirst()
        if queue.isEmpty { phase = .cooldown }
        return entry
    }

    /// ← Left: come back later. The current card moves behind the remaining ones.
    @discardableResult
    public mutating func swipeLeft() -> StackEntry? {
        guard let entry = current else { return nil }
        queue.append(queue.removeFirst())
        return entry
    }

    /// ↑ Up: like. The card stays. Returns the liked exercise id for the app to persist, and records
    /// the like in `selector` so later picks in this workout see it.
    @discardableResult
    public mutating func swipeUp(selector: inout VariationSelector) -> String? {
        guard let id = current?.exerciseID else { return nil }
        selector.setLiked(id)
        return id
    }

    /// ↓ Down: the current exercise's equipment is unavailable. Marks it in `selector` and refills
    /// the slot with an exercise that doesn't need it. Returns the equipment ids for the app to
    /// persist at the current gym (empty for bodyweight exercises, which still get refilled), or nil
    /// when there's no exercise on the current card.
    @discardableResult
    public mutating func swipeDown(
        selector: inout VariationSelector,
        using rng: inout some RandomNumberGenerator
    ) -> Set<String>? {
        guard let entry = current, let exerciseID = entry.exerciseID else { return nil }
        let equipment = selector.exercise(exerciseID)?.equipment ?? []
        selector.markUnavailable(equipment)
        refill(entry, selector: selector, using: &rng)
        return equipment
    }

    // MARK: - Card menu and extra slots

    /// "Never show me this": hides the current exercise in `selector` and refills the slot.
    /// Returns the hidden exercise id for the app to persist.
    @discardableResult
    public mutating func hideCurrent(
        selector: inout VariationSelector,
        using rng: inout some RandomNumberGenerator
    ) -> String? {
        guard let entry = current, let exerciseID = entry.exerciseID else { return nil }
        selector.setHidden(exerciseID)
        refill(entry, selector: selector, using: &rng)
        return exerciseID
    }

    /// "Swap variation": puts a manually chosen exercise on the current card. It's a substitute when
    /// it belongs to another movement type. Fails for an exercise already elsewhere in the stack.
    @discardableResult
    public mutating func swapCurrent(to exerciseID: String, selector: VariationSelector) -> Bool {
        guard var entry = current, let exercise = selector.exercise(exerciseID) else { return false }
        let elsewhere = exerciseIDsInStack.subtracting([entry.exerciseID].compactMap { $0 })
        guard !elsewhere.contains(exerciseID) else { return false }
        entry.fill = exercise.movementType == entry.movementType
            ? .variation(exerciseID: exerciseID)
            : .substitute(exerciseID: exerciseID)
        replace(entry)
        return true
    }

    /// "Add exercise": appends a slot behind the remaining cards. Allowed before and during lifting.
    @discardableResult
    public mutating func addSlot(
        _ movementType: String,
        selector: VariationSelector,
        using rng: inout some RandomNumberGenerator
    ) -> StackEntry? {
        guard phase == .warmup || phase == .lifting else { return nil }
        return append(movementType, selector: selector, using: &rng)
    }

    // MARK: - Private

    @discardableResult
    private mutating func append(
        _ movementType: String,
        selector: VariationSelector,
        using rng: inout some RandomNumberGenerator
    ) -> StackEntry {
        let fill = selector.select(for: movementType, excluding: exerciseIDsInStack, using: &rng)
        let entry = StackEntry(id: (entries.map(\.id).max() ?? -1) + 1, movementType: movementType, fill: fill)
        entries.append(entry)
        queue.append(entry.id)
        return entry
    }

    /// Picks a new exercise for `entry`'s slot. The replaced exercise stays excluded.
    private mutating func refill(
        _ entry: StackEntry,
        selector: VariationSelector,
        using rng: inout some RandomNumberGenerator
    ) {
        var entry = entry
        entry.fill = selector.select(for: entry.movementType, excluding: exerciseIDsInStack, using: &rng)
        replace(entry)
    }

    private mutating func replace(_ entry: StackEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }
}
