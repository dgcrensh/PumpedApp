@testable import PumpedCore

/// A small library for selection and stack tests.
enum Fixture {
    static let movementTypes = [
        SelectionMovementType(id: "squat", primaryMuscles: ["quads", "glutes"]),
        SelectionMovementType(id: "lunge", primaryMuscles: ["quads", "glutes"]),
        SelectionMovementType(id: "press", primaryMuscles: ["chest"]),
        SelectionMovementType(id: "curl", primaryMuscles: ["biceps"]),
    ]

    static let exercises = [
        SelectionExercise(id: "back-squat", movementType: "squat", equipment: ["barbell", "rack"], muscles: ["quads", "glutes"]),
        SelectionExercise(id: "goblet-squat", movementType: "squat", equipment: ["dumbbells"], muscles: ["quads", "glutes"]),
        SelectionExercise(id: "leg-press", movementType: "squat", equipment: ["leg-press"], muscles: ["quads"]),
        SelectionExercise(id: "split-squat", movementType: "lunge", equipment: ["dumbbells"], muscles: ["quads", "glutes"]),
        SelectionExercise(id: "walking-lunge", movementType: "lunge", equipment: [], muscles: ["glutes"]),
        SelectionExercise(id: "bench-press", movementType: "press", equipment: ["barbell", "bench"], muscles: ["chest"]),
        SelectionExercise(id: "db-press", movementType: "press", equipment: ["dumbbells", "bench"], muscles: ["chest"]),
        SelectionExercise(id: "push-up", movementType: "press", equipment: [], muscles: ["chest"]),
        SelectionExercise(id: "barbell-curl", movementType: "curl", equipment: ["barbell"], muscles: ["biceps"]),
    ]

    static func selector(
        unavailable: Set<String> = [],
        history: SelectionHistory = .empty,
        edit: (inout [SelectionExercise]) -> Void = { _ in }
    ) -> VariationSelector {
        var exercises = exercises
        edit(&exercises)
        return VariationSelector(exercises: exercises, movementTypes: movementTypes, unavailableEquipment: unavailable, history: history)
    }
}

extension Array where Element == SelectionExercise {
    mutating func update(_ id: String, _ change: (inout SelectionExercise) -> Void) {
        if let index = firstIndex(where: { $0.id == id }) { change(&self[index]) }
    }
}
