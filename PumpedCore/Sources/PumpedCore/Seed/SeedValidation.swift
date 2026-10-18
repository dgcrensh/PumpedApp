import Foundation

/// A single inconsistency found in a seed library.
public enum SeedIssue: Equatable, Hashable, Sendable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case emptyID(kind: String)
    case emptyName(kind: String, id: String)
    case duplicateID(kind: String, id: String)
    case unknownMovementType(exercise: String, movementType: String)
    case unknownEquipment(exercise: String, equipment: String)
    case unknownMuscle(owner: String, muscle: String)
    case movementTypeWithoutMuscles(String)
    case movementTypeWithoutVariations(String)
    case exerciseWithoutMuscles(String)
    case nonPositiveDuration(owner: String)
    case emptyStretchSequence(String)
    case unknownStretch(sequence: String, stretch: String)

    public var description: String {
        switch self {
        case .unsupportedVersion(let v): "seed version must be >= 1 (got \(v))"
        case .emptyID(let kind): "\(kind) has an empty id"
        case .emptyName(let kind, let id): "\(kind) '\(id)' has an empty name"
        case .duplicateID(let kind, let id): "duplicate \(kind) id '\(id)'"
        case .unknownMovementType(let e, let m): "exercise '\(e)' references unknown movement type '\(m)'"
        case .unknownEquipment(let e, let q): "exercise '\(e)' references unknown equipment '\(q)'"
        case .unknownMuscle(let o, let m): "'\(o)' references unknown muscle group '\(m)'"
        case .movementTypeWithoutMuscles(let m): "movement type '\(m)' has no primary muscles"
        case .movementTypeWithoutVariations(let m): "movement type '\(m)' has no exercises"
        case .exerciseWithoutMuscles(let e): "exercise '\(e)' has no muscles"
        case .nonPositiveDuration(let o): "'\(o)' has a duration <= 0"
        case .emptyStretchSequence(let s): "stretch sequence '\(s)' has no stretches"
        case .unknownStretch(let s, let st): "stretch sequence '\(s)' references unknown stretch '\(st)'"
        }
    }
}

public struct SeedValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public var issues: [SeedIssue]

    public var description: String {
        "Invalid seed library:\n" + issues.map { "  - \($0)" }.joined(separator: "\n")
    }
}

extension SeedLibrary {
    /// Every inconsistency in the library, in a stable order. Empty means valid.
    public func issues() -> [SeedIssue] {
        var issues: [SeedIssue] = []
        if version < 1 { issues.append(.unsupportedVersion(version)) }

        func checkRecords(_ kind: String, _ records: [(id: String, name: String)]) -> Set<String> {
            var seen = Set<String>()
            for record in records {
                if record.id.isEmpty { issues.append(.emptyID(kind: kind)); continue }
                if record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.emptyName(kind: kind, id: record.id))
                }
                if !seen.insert(record.id).inserted {
                    issues.append(.duplicateID(kind: kind, id: record.id))
                }
            }
            return seen
        }

        let muscleIDs = checkRecords("muscle group", muscleGroups.map { ($0.id, $0.name) })
        let equipmentIDs = checkRecords("equipment", equipment.map { ($0.id, $0.name) })
        let movementIDs = checkRecords("movement type", movementTypes.map { ($0.id, $0.name) })
        _ = checkRecords("exercise", exercises.map { ($0.id, $0.name) })
        _ = checkRecords("cardio option", cardioOptions.map { ($0.id, $0.name) })
        let stretchIDs = checkRecords("stretch", stretches.map { ($0.id, $0.name) })
        _ = checkRecords("stretch sequence", stretchSequences.map { ($0.id, $0.name) })

        for movement in movementTypes {
            if movement.primaryMuscles.isEmpty { issues.append(.movementTypeWithoutMuscles(movement.id)) }
            for muscle in movement.primaryMuscles where !muscleIDs.contains(muscle) {
                issues.append(.unknownMuscle(owner: movement.id, muscle: muscle))
            }
        }

        var movementsWithVariations = Set<String>()
        for exercise in exercises {
            if movementIDs.contains(exercise.movementType) {
                movementsWithVariations.insert(exercise.movementType)
            } else {
                issues.append(.unknownMovementType(exercise: exercise.id, movementType: exercise.movementType))
            }
            for item in exercise.equipment where !equipmentIDs.contains(item) {
                issues.append(.unknownEquipment(exercise: exercise.id, equipment: item))
            }
            if exercise.muscles.isEmpty { issues.append(.exerciseWithoutMuscles(exercise.id)) }
            for muscle in exercise.muscles where !muscleIDs.contains(muscle) {
                issues.append(.unknownMuscle(owner: exercise.id, muscle: muscle))
            }
        }
        for movement in movementTypes where !movementsWithVariations.contains(movement.id) {
            issues.append(.movementTypeWithoutVariations(movement.id))
        }

        for stretch in stretches where stretch.defaultDurationSec <= 0 {
            issues.append(.nonPositiveDuration(owner: stretch.id))
        }
        for sequence in stretchSequences {
            if sequence.items.isEmpty { issues.append(.emptyStretchSequence(sequence.id)) }
            for item in sequence.items {
                if !stretchIDs.contains(item.stretch) {
                    issues.append(.unknownStretch(sequence: sequence.id, stretch: item.stretch))
                }
                if item.durationSec <= 0 {
                    issues.append(.nonPositiveDuration(owner: "\(sequence.id)/\(item.stretch)"))
                }
            }
        }
        return issues
    }

    /// Throws `SeedValidationError` listing every issue if the library is inconsistent.
    public func validate() throws {
        let found = issues()
        if !found.isEmpty { throw SeedValidationError(issues: found) }
    }
}
