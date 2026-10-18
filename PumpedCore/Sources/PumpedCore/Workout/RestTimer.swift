import Foundation

/// The rest timer between sets (spec §6.2). It stores an absolute end date rather than a ticking
/// counter, so it keeps time while the app is backgrounded or killed.
public struct RestTimer: Equatable, Codable, Sendable {
    /// When the rest is over. Nil when no rest is running (skipped, or none started yet).
    public private(set) var endsAt: Date?

    /// What "+30s" adds.
    public static let extensionSeconds = 30

    public init(endsAt: Date? = nil) {
        self.endsAt = endsAt
    }

    /// Starts a fresh rest of `seconds` from `now`, replacing any rest still running.
    public mutating func start(seconds: Int, at now: Date) {
        endsAt = seconds > 0 ? now.addingTimeInterval(TimeInterval(seconds)) : nil
    }

    /// Stops the rest early.
    public mutating func skip() {
        endsAt = nil
    }

    /// Adds `seconds` to a running rest. Once the rest is over, it restarts from `now` instead, so a
    /// late tap still buys that much more time.
    public mutating func extend(by seconds: Int = extensionSeconds, at now: Date) {
        guard let endsAt, endsAt > now else {
            start(seconds: seconds, at: now)
            return
        }
        self.endsAt = endsAt.addingTimeInterval(TimeInterval(seconds))
    }

    public func isRunning(at now: Date) -> Bool {
        remaining(at: now) > 0
    }

    /// Seconds left, never negative.
    public func remaining(at now: Date) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(endsAt.timeIntervalSince(now), 0)
    }

    /// Whole seconds left for display, rounded up so "0:00" only shows once the rest is over.
    public func displaySeconds(at now: Date) -> Int {
        Int(remaining(at: now).rounded(.up))
    }

    /// Choices offered in Settings for each exercise type: 0:15 to 10:00 in 15-second steps.
    public static let settingRange = 15...600
    public static let settingStep = 15
}

/// "2:05", or "1:02:05" past an hour.
public enum CountdownText {
    public static func format(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
