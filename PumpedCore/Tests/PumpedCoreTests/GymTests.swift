import XCTest
@testable import PumpedCore

final class EquipmentAvailabilityTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testMarkLastsSevenDays() {
        var availability = EquipmentAvailability()
        availability.mark(["rack", "barbell"], at: "gym-a", on: start)
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-a", now: start), ["rack", "barbell"])
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-a", now: start + 7 * day - 1), ["rack", "barbell"])
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-a", now: start + 7 * day), [])
    }

    func testRemarkingResetsTheWindow() {
        var availability = EquipmentAvailability()
        availability.mark(["rack"], at: "gym-a", on: start)
        availability.mark(["rack"], at: "gym-a", on: start + 5 * day)
        XCTAssertEqual(availability.marks.count, 1)
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-a", now: start + 10 * day), ["rack"])
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-a", now: start + 12 * day), [])
    }

    func testOlderMarkDoesNotShortenTheWindow() {
        let availability = EquipmentAvailability(marks: [
            .init(gymID: "gym-a", equipmentID: "rack", markedAt: start + 5 * day),
            .init(gymID: "gym-a", equipmentID: "rack", markedAt: start),
        ])
        XCTAssertEqual(availability.marks.map(\.markedAt), [start + 5 * day])
    }

    func testGymsAreIndependent() {
        var availability = EquipmentAvailability()
        availability.mark(["rack"], at: "gym-a", on: start)
        availability.mark(["cable"], at: "gym-b", on: start)
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-a", now: start), ["rack"])
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-b", now: start), ["cable"])
    }

    func testNoGymFiltersNothing() {
        var availability = EquipmentAvailability()
        availability.mark(["rack"], at: "gym-a", on: start)
        XCTAssertEqual(availability.unavailableEquipment(at: nil, now: start), [])
    }

    func testClear() {
        var availability = EquipmentAvailability()
        availability.mark(["rack", "cable"], at: "gym-a", on: start)
        availability.mark(["rack"], at: "gym-b", on: start)
        availability.clear(at: "gym-a", equipmentID: "rack")
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-a", now: start), ["cable"])
        availability.clear(at: "gym-a")
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-a", now: start), [])
        XCTAssertEqual(availability.unavailableEquipment(at: "gym-b", now: start), ["rack"])
    }

    func testFeedsTheSelector() {
        var availability = EquipmentAvailability()
        availability.mark(["rack"], at: "gym-a", on: start)
        let selector = Fixture.selector(unavailable: availability.unavailableEquipment(at: "gym-a", now: start + day))
        XCTAssertEqual(selector.weightedCandidates(for: "squat", excluding: []).map(\.id), ["goblet-squat", "leg-press"])
    }
}

final class GymMatcherTests: XCTestCase {
    private let origin = Coordinate(latitude: 40.0, longitude: -105.0)

    /// A point `meters` north of `origin` (1° latitude ≈ 111,195 m on the haversine sphere).
    private func north(_ meters: Double) -> Coordinate {
        Coordinate(latitude: origin.latitude + meters / 111_194.93, longitude: origin.longitude)
    }

    func testDistance() {
        XCTAssertEqual(origin.distance(to: north(100)), 100, accuracy: 0.5)
        XCTAssertEqual(origin.distance(to: origin), 0)
    }

    func testMatchesWithinRadius() {
        let gym = KnownGym(id: "a", location: north(140))
        XCTAssertEqual(GymMatcher.match(origin, among: [gym])?.id, "a")
    }

    func testNoMatchOutsideRadius() {
        XCTAssertNil(GymMatcher.match(origin, among: [KnownGym(id: "a", location: north(160))]))
        XCTAssertNil(GymMatcher.match(origin, among: []))
    }

    func testPicksTheNearestGym() {
        let gyms = [KnownGym(id: "far", location: north(120)), KnownGym(id: "near", location: north(-50))]
        XCTAssertEqual(GymMatcher.match(origin, among: gyms)?.id, "near")
    }
}
