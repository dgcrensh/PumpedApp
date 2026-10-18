import Foundation
import SwiftData

/// Data UI tests ask for with launch arguments. Only used with the in-memory store.
@MainActor
enum UITestingData {
    /// An active "PPL" split whose next day, "Push", has two movement slots.
    static func addSampleSplit(to context: ModelContext) {
        let split = SplitEditing.createSplit(named: "PPL", in: context)
        let push = SplitEditing.addDay(named: "Push", to: split, in: context)
        SplitEditing.addDay(named: "Pull", to: split, in: context)
        for id in ["horizontal-press", "triceps-extension"] {
            if let movementType = try? context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first {
                SplitEditing.addSlot(movementType, to: push, in: context)
            }
        }
        try? context.save()
    }
}
