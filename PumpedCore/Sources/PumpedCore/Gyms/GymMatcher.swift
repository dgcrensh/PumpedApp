import Foundation

public struct Coordinate: Equatable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in meters (haversine).
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

public struct KnownGym: Equatable, Codable, Sendable {
    public var id: String
    public var location: Coordinate
    /// Match radius in meters.
    public var radius: Double

    public init(id: String, location: Coordinate, radius: Double = GymMatcher.defaultRadius) {
        self.id = id
        self.location = location
        self.radius = radius
    }
}

/// Finds the gym the user is at when a workout starts (spec §8).
public enum GymMatcher {
    public static let defaultRadius = 150.0

    /// The nearest known gym whose radius contains `location`, or nil ("New gym? Name it").
    public static func match(_ location: Coordinate, among gyms: [KnownGym]) -> KnownGym? {
        gyms
            .map { (gym: $0, distance: location.distance(to: $0.location)) }
            .filter { $0.distance <= $0.gym.radius }
            .min { $0.distance < $1.distance }?
            .gym
    }
}
