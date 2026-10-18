import Foundation

/// Equipment the user has marked unavailable at each gym by swiping down (spec §8).
///
/// A mark lasts `window` (7 days in v1). Marking the same equipment again restarts the window.
public struct EquipmentAvailability: Equatable, Codable, Sendable {
    public static let defaultWindow: TimeInterval = 7 * 24 * 60 * 60

    public struct Mark: Hashable, Codable, Sendable {
        public var gymID: String
        public var equipmentID: String
        public var markedAt: Date

        public init(gymID: String, equipmentID: String, markedAt: Date) {
            self.gymID = gymID
            self.equipmentID = equipmentID
            self.markedAt = markedAt
        }
    }

    /// At most one mark per gym and equipment: the latest.
    public private(set) var marks: [Mark]
    public var window: TimeInterval

    public init(marks: [Mark] = [], window: TimeInterval = defaultWindow) {
        self.marks = []
        self.window = window
        for mark in marks { record(mark) }
    }

    /// Records a down-swipe. Restarts the window for equipment that's already marked.
    public mutating func mark(_ equipment: Set<String>, at gymID: String, on date: Date) {
        for id in equipment.sorted() {
            record(Mark(gymID: gymID, equipmentID: id, markedAt: date))
        }
    }

    /// Settings → Gyms: clear one piece of equipment, or all of a gym's marks when `equipmentID` is nil.
    public mutating func clear(at gymID: String, equipmentID: String? = nil) {
        marks.removeAll { $0.gymID == gymID && (equipmentID == nil || $0.equipmentID == equipmentID) }
    }

    /// Marks at a gym that are still in effect at `now`.
    public func activeMarks(at gymID: String, now: Date) -> [Mark] {
        marks.filter { $0.gymID == gymID && isActive($0, now: now) }
    }

    /// Equipment ids to exclude at a gym. With no gym, nothing is filtered.
    public func unavailableEquipment(at gymID: String?, now: Date) -> Set<String> {
        guard let gymID else { return [] }
        return Set(activeMarks(at: gymID, now: now).map(\.equipmentID))
    }

    public func expiry(of mark: Mark) -> Date {
        mark.markedAt.addingTimeInterval(window)
    }

    private func isActive(_ mark: Mark, now: Date) -> Bool {
        now >= mark.markedAt && now < expiry(of: mark)
    }

    private mutating func record(_ mark: Mark) {
        if let index = marks.firstIndex(where: { $0.gymID == mark.gymID && $0.equipmentID == mark.equipmentID }) {
            if mark.markedAt > marks[index].markedAt { marks[index] = mark }
        } else {
            marks.append(mark)
        }
    }
}
