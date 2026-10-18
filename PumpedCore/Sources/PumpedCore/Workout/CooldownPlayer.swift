import Foundation

/// The cool-down stretch player (spec §6.3): one stretch at a time with a countdown that
/// auto-advances, plus pause, skip and back.
///
/// Time is kept as an absolute end date for the current stretch, so the player catches up correctly
/// after the app was in the background: `update(at:)` moves past every stretch whose time ran out.
/// It's `Codable` so the app can save it and resume after being killed.
public struct CooldownPlayer: Equatable, Codable, Sendable {
    /// Hold time of each stretch, in order.
    public let durations: [Int]
    /// The stretch on screen. Equals `durations.count` once the sequence is done.
    public private(set) var index: Int
    /// End of the current stretch while running.
    public private(set) var endsAt: Date?
    /// Seconds left on the current stretch while paused.
    public private(set) var pausedRemaining: TimeInterval?

    /// Starts on the first stretch, running from `now`.
    public init(durations: [Int], at now: Date) {
        self.durations = durations.map { max($0, 1) }
        index = 0
        if let first = self.durations.first {
            endsAt = now.addingTimeInterval(TimeInterval(first))
        }
    }

    public var isFinished: Bool { index >= durations.count }
    public var isPaused: Bool { pausedRemaining != nil && !isFinished }

    /// Seconds left on the current stretch.
    public func remaining(at now: Date) -> TimeInterval {
        if isFinished { return 0 }
        if let pausedRemaining { return pausedRemaining }
        guard let endsAt else { return 0 }
        return max(endsAt.timeIntervalSince(now), 0)
    }

    /// Whole seconds left for display, rounded up.
    public func displaySeconds(at now: Date) -> Int {
        Int(remaining(at: now).rounded(.up))
    }

    /// Moves past every stretch whose time has run out by `now`, chaining each next stretch from
    /// the previous one's end. Returns how many stretches it advanced (0 when nothing changed).
    @discardableResult
    public mutating func update(at now: Date) -> Int {
        guard !isFinished, pausedRemaining == nil, var end = endsAt else { return 0 }
        var advanced = 0
        while end <= now {
            index += 1
            advanced += 1
            guard !isFinished else {
                endsAt = nil
                return advanced
            }
            end = end.addingTimeInterval(TimeInterval(durations[index]))
        }
        endsAt = end
        return advanced
    }

    public mutating func pause(at now: Date) {
        update(at: now)
        guard !isFinished, pausedRemaining == nil else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    public mutating func resume(at now: Date) {
        guard !isFinished, let pausedRemaining else { return }
        endsAt = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    /// Ends the current stretch now and starts the next one with its full time.
    public mutating func skip(at now: Date) {
        update(at: now)
        guard !isFinished else { return }
        go(to: index + 1, at: now)
    }

    /// Goes to the previous stretch with its full time, or restarts the first one.
    public mutating func back(at now: Date) {
        update(at: now)
        go(to: max(min(index, durations.count) - 1, 0), at: now)
    }

    /// Jumps to `newIndex` with its full time, keeping the paused/running state.
    private mutating func go(to newIndex: Int, at now: Date) {
        guard !durations.isEmpty else { return }
        let wasPaused = pausedRemaining != nil
        index = min(newIndex, durations.count)
        guard !isFinished else {
            endsAt = nil
            pausedRemaining = nil
            return
        }
        let full = TimeInterval(durations[index])
        if wasPaused {
            pausedRemaining = full
            endsAt = nil
        } else {
            endsAt = now.addingTimeInterval(full)
        }
    }
}
