import Foundation
import PumpedCore
import SwiftData

/// Gym mutations and lookups for workout start and Settings → Gyms (spec §8), kept out of the views
/// so they can be unit tested.
@MainActor
enum GymEditing {
    /// Name used when a new gym is saved with a blank name.
    static let defaultName = "My gym"

    static func allGyms(in context: ModelContext) -> [Gym] {
        (try? context.fetch(FetchDescriptor<Gym>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    static func gym(_ id: String, in context: ModelContext) -> Gym? {
        try? context.fetch(FetchDescriptor<Gym>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: Detection

    static func knownGym(_ gym: Gym) -> KnownGym {
        KnownGym(id: gym.id, location: Coordinate(latitude: gym.latitude, longitude: gym.longitude), radius: gym.radius)
    }

    /// Which gym prompt to show for the location fetched at workout start.
    static func detect(_ fix: LocationFix, in context: ModelContext) -> GymDetection {
        GymDetection.resolve(fix, among: allGyms(in: context).map(knownGym))
    }

    // MARK: Editing

    /// "New gym? Name it": saves the gym at the coordinates the workout started at.
    @discardableResult
    static func createGym(named name: String, at location: Coordinate, in context: ModelContext) -> Gym {
        let gym = Gym(name: cleaned(name) ?? defaultName, latitude: location.latitude, longitude: location.longitude)
        context.insert(gym)
        save(context)
        return gym
    }

    /// Renames a gym. A blank name keeps the old one.
    static func rename(_ gym: Gym, to name: String, in context: ModelContext) {
        guard let name = cleaned(name) else { return }
        gym.name = name
        save(context)
    }

    /// Deletes a gym and its unavailable equipment. Workouts at it keep their sets and show no gym.
    static func delete(_ gym: Gym, in context: ModelContext) {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        for session in sessions where session.gym === gym {
            session.gym = nil
        }
        context.delete(gym)
        save(context)
    }

    /// Tapping the workout header: the rest of the workout picks variations for `gym`.
    static func changeGym(of session: WorkoutSession, to gym: Gym?, in context: ModelContext) {
        session.gym = gym
        save(context)
    }

    // MARK: Unavailable equipment

    struct UnavailableItem: Identifiable {
        let row: EquipmentUnavailability
        let name: String
        let expiresAt: Date
        var id: PersistentIdentifier { row.persistentModelID }
    }

    /// Equipment still excluded at the gym, by name, with when each mark runs out.
    static func unavailableEquipment(at gym: Gym, now: Date = .now) -> [UnavailableItem] {
        let rows = gym.unavailableEquipment.compactMap { row in row.equipment.map { (row: row, equipment: $0) } }
        let availability = EquipmentAvailability(marks: rows.map {
            EquipmentAvailability.Mark(gymID: gym.id, equipmentID: $0.equipment.id, markedAt: $0.row.markedAt)
        })
        let active = Dictionary(
            availability.activeMarks(at: gym.id, now: now).map { ($0.equipmentID, availability.expiry(of: $0)) },
            uniquingKeysWith: { max($0, $1) }
        )
        return rows
            .compactMap { item in
                active[item.equipment.id].map { UnavailableItem(row: item.row, name: item.equipment.name, expiresAt: $0) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Makes one piece of equipment available at its gym again.
    static func clear(_ row: EquipmentUnavailability, in context: ModelContext) {
        row.gym?.unavailableEquipment.removeAll { $0 === row }
        context.delete(row)
        save(context)
    }

    /// Makes everything available at the gym again.
    static func clearAll(at gym: Gym, in context: ModelContext) {
        let rows = gym.unavailableEquipment
        gym.unavailableEquipment.removeAll()
        for row in rows { context.delete(row) }
        save(context)
    }

    // MARK: Helpers

    private static func cleaned(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func save(_ context: ModelContext) {
        try? context.save()
    }
}
