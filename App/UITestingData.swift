import Foundation
import PumpedCore
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

    /// Twelve finished weekly workouts of Barbell Bench Press, three sets each, getting
    /// heavier every week, so the last one holds the PRs.
    static func addSampleHistory(to context: ModelContext, now: Date = .now) {
        guard let bench = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == "barbell-bench-press" })).first else { return }
        for week in 0..<12 {
            let start = now.addingTimeInterval(-Double(12 - week) * 7 * 86_400)
            let session = WorkoutSession(startedAt: start, phase: .complete)
            context.insert(session)
            session.endedAt = start.addingTimeInterval(50 * 60)
            session.cooldownCompleted = true
            let entry = WorkoutEntry(slotOrder: 0, movementTypeID: "horizontal-press", exercise: bench, stackPosition: -1)
            entry.status = .done
            context.insert(entry)
            session.entries.append(entry)
            let weight = 135 + Double(week) * 5
            for (index, reps) in [5, 5, 4].enumerated() {
                let set = SetLog(reps: reps, weightLb: weight, loggedAt: start.addingTimeInterval(Double(index + 1) * 180))
                context.insert(set)
                entry.sets.append(set)
            }
        }
        try? context.save()
    }
}
