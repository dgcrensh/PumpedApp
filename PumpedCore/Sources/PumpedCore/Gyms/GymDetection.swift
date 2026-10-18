import Foundation

/// What a one-shot location fetch at workout start came back with.
public enum LocationFix: Equatable, Sendable {
    case located(Coordinate)
    /// The user said no to location, or it's restricted.
    case denied
    /// No fix in time, or Location Services failed.
    case unavailable
}

/// Which gym prompt a workout starts with (spec §8).
public enum GymDetection: Equatable, Sendable {
    /// A known gym contains the location: use it, shown on the workout header.
    case matched(gymID: String)
    /// Somewhere new: "New gym? Name it", saving these coordinates, or "No gym".
    case newGym(Coordinate)
    /// No location to go on: pick from the known gyms, or "No gym".
    case pickGym
    /// No location and no gyms to pick from, so the workout starts with no gym.
    case noGym

    public static func resolve(_ fix: LocationFix, among gyms: [KnownGym]) -> GymDetection {
        switch fix {
        case .located(let location):
            if let gym = GymMatcher.match(location, among: gyms) { return .matched(gymID: gym.id) }
            return .newGym(location)
        case .denied, .unavailable:
            return gyms.isEmpty ? .noGym : .pickGym
        }
    }
}
