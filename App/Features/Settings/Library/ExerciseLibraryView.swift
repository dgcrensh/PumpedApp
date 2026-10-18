import SwiftData
import SwiftUI

/// Read-only list of every exercise, grouped by movement type.
struct ExerciseLibraryView: View {
    @Query(sort: \MovementType.name) private var movementTypes: [MovementType]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var searchText = ""

    private var filtered: [Exercise] {
        guard !searchText.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        let byMovement = Dictionary(grouping: filtered) { $0.movementType?.id }
        List {
            ForEach(movementTypes) { movement in
                if let rows = byMovement[movement.id] {
                    Section {
                        ForEach(rows) { ExerciseRow(exercise: $0) }
                    } header: {
                        MovementHeader(name: movement.name, muscles: movement.primaryMuscles, count: rows.count)
                    }
                }
            }
            if let rows = byMovement[String?.none] {
                Section("No movement type") {
                    ForEach(rows) { ExerciseRow(exercise: $0) }
                }
            }
        }
        .overlay {
            if filtered.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises")
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MovementHeader: View {
    let name: String
    let muscles: [String]
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(name) (\(count))")
            Text(MuscleGroupNames.list(muscles))
                .font(.caption)
                .textCase(nil)
        }
    }
}

private struct ExerciseRow: View {
    let exercise: Exercise

    private var equipmentText: String {
        let names = exercise.equipment.map(\.name).sorted()
        return names.isEmpty ? "Bodyweight" : names.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(exercise.name)
                    if exercise.isLiked {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .accessibilityLabel("Liked")
                    }
                    if exercise.isCustom {
                        Text("Custom")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    if exercise.isHidden {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Hidden")
                    }
                }
                Text(equipmentText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(MuscleGroupNames.list(exercise.muscles))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(exercise.exerciseType.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        ExerciseLibraryView()
    }
    .modelContainer(PreviewData.container)
}
