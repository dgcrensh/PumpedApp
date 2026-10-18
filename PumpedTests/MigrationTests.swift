import SwiftData
import XCTest
@testable import Pumped

@MainActor
final class MigrationTests: XCTestCase {
    /// A store written by schema version 1 opens through the migration plan with its workouts intact.
    func testVersion1StoreMigratesToCurrentSchema() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("v1-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let schema = Schema(versionedSchema: PumpedSchemaV1.self)
            let v1 = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            let session = PumpedSchemaV1.WorkoutSession(phase: .lifting)
            v1.mainContext.insert(session)
            let entry = PumpedSchemaV1.WorkoutEntry(slotOrder: 0, exercise: nil, stackPosition: 0)
            v1.mainContext.insert(entry)
            session.entries.append(entry)
            let set = PumpedSchemaV1.SetLog(reps: 5, weightLb: 225)
            v1.mainContext.insert(set)
            entry.sets.append(set)
            try v1.mainContext.save()
        }

        let current = try PumpedStore.makeContainer(url: url)
        let sessions = try current.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        XCTAssertEqual(sessions.count, 1)
        let entry = try XCTUnwrap(sessions.first?.entries.first)
        XCTAssertNil(entry.movementTypeID)
        XCTAssertEqual(entry.sets.map(\.weightLb), [225])
    }
}
