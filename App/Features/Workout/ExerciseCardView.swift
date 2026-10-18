import PumpedCore
import SwiftData
import SwiftUI

/// One card's contents (spec §6.2): the exercise, last session's sets, today's sets, the reps and
/// weight steppers (prefilled from last time) and Log set.
struct ExerciseCardView: View {
    @Environment(\.modelContext) private var context
    let entry: WorkoutEntry
    let session: WorkoutSession
    let onSwap: () -> Void
    let onHide: () -> Void

    @State private var lastTime: LastTime?
    /// Every earlier set of this exercise, for the PR badge.
    @State private var history: [SetValues] = []
    /// Records the set just logged broke, for the "New PR" flash.
    @State private var newRecords: [PersonalRecord] = []
    @State private var showsProgress = false
    @State private var slotName = ""
    @State private var reps = SetValues.fallback.reps
    @State private var weight = SetValues.fallback.weightLb
    @FocusState private var isEditingWeight: Bool

    private struct LastTime {
        let date: Date
        let sets: [SetValues]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let exercise = entry.exercise {
                history(for: exercise)
                Divider()
                RestTimerView(session: session)
                logging
            } else {
                unavailable
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .sensoryFeedback(.success, trigger: entry.sets.count) { old, new in new > old }
        .task(id: entry.exercise?.id) { load() }
        .sheet(isPresented: $showsProgress) {
            if let exercise = entry.exercise {
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                        .historyDestinations()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsProgress = false }
                            }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditingWeight = false }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if entry.isSubstitute {
                    Text("Substitute for \(slotName)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(.orange)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
                if let exercise = entry.exercise {
                    Button {
                        showsProgress = true
                    } label: {
                        Text(exercise.name)
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("Shows progress and PRs")
                    .accessibilityIdentifier("card-exercise-name")
                } else {
                    Text("No available variation")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                }
                if let exercise = entry.exercise {
                    Text(subtitle(for: exercise))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if entry.exercise?.isLiked == true {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .accessibilityLabel("Liked")
            }
            menu
        }
    }

    private var menu: some View {
        Menu {
            Button(action: onSwap) {
                Label("Swap variation", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!entry.sets.isEmpty)
            if let exercise = entry.exercise {
                if exercise.isLiked {
                    Button {
                        WorkoutFlow.setLiked(exercise, false, in: context)
                    } label: {
                        Label("Unlike", systemImage: "heart.slash")
                    }
                } else {
                    Button {
                        WorkoutFlow.setLiked(exercise, true, in: context)
                    } label: {
                        Label("Like", systemImage: "heart")
                    }
                }
                Button(role: .destructive, action: onHide) {
                    Label("Never show me this", systemImage: "eye.slash")
                }
                .disabled(!entry.sets.isEmpty)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .padding(4)
        }
        .accessibilityLabel("Exercise options")
    }

    private func history(for exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastTime {
                Text("Last time, \(lastTime.date.formatted(.dateTime.month(.abbreviated).day())): \(SetPrefill.summary(lastTime.sets))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("First time logging this one")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            let today = entry.orderedSets
            if !today.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today: \(SetPrefill.summary(today.map(WorkoutFlow.values)))")
                        .font(.callout.weight(.semibold))
                        .accessibilityIdentifier("today-sets")
                    Spacer(minLength: 8)
                    Button {
                        if let last = today.last { WorkoutFlow.deleteSet(last, in: context) }
                        newRecords = []
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .accessibilityLabel("Remove last set")
                }
                prBadge(today.map(WorkoutFlow.values))
            }
        }
    }

    /// Today's PRs on this card (spec §9), recomputed as sets are logged or removed.
    @ViewBuilder
    private func prBadge(_ today: [SetValues]) -> some View {
        let records = PersonalRecords.hits(today: today, history: history)
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label(newRecords.isEmpty ? "PR" : "New PR!", systemImage: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(.black)
                    .background(.yellow, in: Capsule())
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    Text(record.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pr-badge")
        }
    }

    private var logging: some View {
        VStack(spacing: 12) {
            Stepper(value: $reps, in: 1...100) {
                Text("\(reps) reps")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                TextField("Weight", value: $weight, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isEditingWeight)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: 80)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Weight in pounds")
                Text("lb")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("+5 lb") { weight = SetPrefill.stepWeight(weight, by: 1) }
                    .buttonStyle(.bordered)
                Stepper(
                    "Weight",
                    onIncrement: { weight = SetPrefill.stepWeight(weight, by: 1) },
                    onDecrement: { weight = SetPrefill.stepWeight(weight, by: -1) }
                )
                .labelsHidden()
            }
            Button(action: logSet) {
                Text("Log set")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing left to pick for \(slotName.isEmpty ? "this slot" : slotName) here. Swap one in by hand, or swipe the card away.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Swap variation", action: onSwap)
                .buttonStyle(.bordered)
        }
    }

    // MARK: Actions

    private func logSet() {
        isEditingWeight = false
        let values = SetValues(reps: reps, weightLb: max(weight, 0))
        newRecords = PersonalRecords.newRecords(
            set: values,
            earlierToday: entry.orderedSets.map(WorkoutFlow.values),
            history: history
        )
        WorkoutFlow.logSet(values, on: entry, in: context)
        RestTimerService.sync(session)
        prefill()
    }

    private func load() {
        if let id = entry.movementTypeID {
            slotName = (try? context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first?.name) ?? ""
        }
        lastTime = entry.exercise
            .flatMap { WorkoutFlow.lastSets(of: $0.id, before: session, in: context) }
            .map { LastTime(date: $0.date, sets: $0.sets) }
        history = entry.exercise.map { WorkoutFlow.allSets(of: $0.id, before: session, in: context) } ?? []
        newRecords = []
        prefill()
    }

    private func prefill() {
        let values = SetPrefill.values(today: entry.orderedSets.map(WorkoutFlow.values), lastSession: lastTime?.sets ?? [])
        reps = values.reps
        weight = values.weightLb
    }

    private func subtitle(for exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted()
        let parts = [exercise.movementType?.name, equipment.isEmpty ? "Bodyweight" : equipment.joined(separator: ", ")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}
