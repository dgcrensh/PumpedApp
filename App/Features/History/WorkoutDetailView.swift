import PumpedCore
import SwiftData
import SwiftUI

/// One finished workout (spec §9): its warmup, every logged set, the cool-down and the PRs it set.
/// Sets can be edited or deleted, and the PRs follow.
struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var context
    let session: WorkoutSession

    @State private var editing: SetLog?

    var body: some View {
        // Read here so edits to any set redraw the PRs.
        let entries = trainedEntries
        let prs = HistoryData.prs(in: session, context: context)
        List {
            overview
            if !prs.isEmpty {
                Section("PRs") {
                    ForEach(Array(prs.enumerated()), id: \.offset) { _, hit in
                        PRLabel(title: hit.exerciseName, record: hit.record)
                    }
                }
            }
            ForEach(entries) { entry in
                Section {
                    if let exercise = entry.exercise {
                        NavigationLink(value: exercise) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(.headline)
                                if entry.isSubstitute {
                                    Text("Substitute")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .accessibilityIdentifier("exercise-link")
                    }
                    ForEach(Array(entry.orderedSets.enumerated()), id: \.element.persistentModelID) { index, set in
                        Button {
                            editing = set
                        } label: {
                            LabeledContent("Set \(index + 1)", value: WorkoutFlow.values(set).summary)
                                .foregroundStyle(.primary)
                        }
                        .accessibilityIdentifier("set-row")
                        .swipeActions {
                            Button("Delete", role: .destructive) { HistoryData.delete(set, in: context) }
                        }
                    }
                }
            }
            if entries.isEmpty {
                Section {
                    Text("No sets logged")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Cool-down") {
                Text(session.cooldownCompleted ? "Finished" : "Skipped")
            }
        }
        .navigationTitle(session.splitDay?.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { set in
            SetEditSheet(set: set)
        }
    }

    private var trainedEntries: [WorkoutEntry] {
        session.entries
            .filter { !$0.sets.isEmpty }
            .sorted { $0.slotOrder < $1.slotOrder }
    }

    private var overview: some View {
        Section {
            LabeledContent("Date", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Duration", value: WorkoutSummary.durationText(session.duration))
            LabeledContent("Gym", value: session.gym?.name ?? "No gym")
            if let warmup = session.warmup {
                LabeledContent("Warmup", value: warmupText(warmup))
            } else {
                LabeledContent("Warmup", value: "Skipped")
            }
        }
    }

    private func warmupText(_ warmup: WarmupLog) -> String {
        var parts = [warmup.cardio?.name ?? "Cardio", "\(warmup.durationSec / 60) min"]
        if let distance = warmup.distanceMi {
            parts.append("\(distance.formatted(.number.precision(.fractionLength(0...2)))) mi")
        }
        return parts.joined(separator: " · ")
    }
}

/// A PR with what it was set on, as in the workout summary.
struct PRLabel: View {
    let title: String
    let record: PersonalRecord

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(record.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
        }
    }
}

/// Edits one logged set's reps and weight.
struct SetEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let set: SetLog

    @State private var reps = 0
    @State private var weight = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $reps, in: 1...100) {
                    Text("\(reps) reps")
                        .monospacedDigit()
                }
                HStack {
                    TextField("Weight", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .accessibilityLabel("Weight in pounds")
                        .accessibilityIdentifier("edit-weight")
                    Text("lb")
                        .foregroundStyle(.secondary)
                    Stepper(
                        "Weight",
                        onIncrement: { weight = SetPrefill.stepWeight(weight, by: 1) },
                        onDecrement: { weight = SetPrefill.stepWeight(weight, by: -1) }
                    )
                    .labelsHidden()
                }
                Section {
                    Button("Delete set", role: .destructive) {
                        HistoryData.delete(set, in: context)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HistoryData.update(set, to: SetValues(reps: reps, weightLb: weight), in: context)
                        dismiss()
                    }
                }
            }
            .onAppear {
                reps = set.reps
                weight = set.weightLb
            }
        }
        .presentationDetents([.medium])
    }
}
