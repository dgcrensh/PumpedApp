import SwiftData
import SwiftUI

/// Workout tab (spec §10): the next split day with Start, or Resume for a workout in progress.
struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var inProgress: [WorkoutSession]
    @Query(filter: #Predicate<Split> { $0.isActive }) private var activeSplits: [Split]

    @State private var presented: WorkoutSession?
    @State private var isLocating = false
    /// Asking which gym this is, after location didn't match one.
    @State private var gymPrompt: GymPromptSheet.Reason?
    /// The prompt's answer; the workout starts once the prompt is gone.
    @State private var gymChoice: GymChoice?
    @State private var discarding: WorkoutSession?
    @State private var didAutoResume = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Workout")
        }
        .sheet(item: $gymPrompt, onDismiss: startWithChosenGym) { reason in
            GymPromptSheet(reason: reason) { gymChoice = $0 }
        }
        .fullScreenCover(item: $presented, onDismiss: discardIfAsked) { session in
            ActiveWorkoutView(session: session) { discarding = session }
        }
        .onAppear {
            // Reopening the app mid-workout goes straight back to it.
            guard !didAutoResume else { return }
            didAutoResume = true
            presented = inProgress.first
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session = inProgress.first {
            resume(session)
        } else if let split = activeSplits.first, let day = SplitEditing.nextDay(of: split) {
            start(day, of: split)
        } else if let split = activeSplits.first {
            ContentUnavailableView {
                Label("\(split.name) has no days", systemImage: "calendar.badge.plus")
            } description: {
                Text("Add a day, like Push or Legs, and its movements to start training.")
            } actions: {
                NavigationLink("Edit \(split.name)") { SplitDetailView(split: split) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "No split to train",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Create a split with at least one day in the Splits tab, then start your workout here.")
            )
        }
    }

    private func resume(_ session: WorkoutSession) -> some View {
        List {
            Section("In progress") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.splitDay?.name ?? "Workout")
                        .font(.title2.bold())
                    Text(resumeDetail(session))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bigButton("Resume workout") { presented = session }
        }
    }

    private func start(_ day: SplitDay, of split: Split) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.name)
                        .font(.title2.bold())
                    Text(SplitCycleText.summary(for: split))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text(split.name)
            }
            Section {
                ForEach(day.orderedSlots) { slot in
                    Text(slot.movementType?.name ?? "Unknown movement")
                }
                if day.slots.isEmpty {
                    NavigationLink("Add movements to \(day.name)") { SplitDayEditorView(day: day) }
                }
            } header: {
                Text("Movements")
            } footer: {
                if day.slots.isEmpty {
                    Text("\(day.name) has no movements yet, so there's nothing to lift. Add some, or pick a different next day in the Splits tab.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bigButton(isLocating ? "Finding your gym…" : "Start workout") {
                Task {
                    await detectGymAndStart()
                    // The rest timer notifies at zero; ask the first time a workout starts.
                    await RestTimerService.requestPermission()
                }
            }
            .disabled(isLocating || day.slots.isEmpty)
        }
    }

    // MARK: Starting

    /// Spec §8: a known gym nearby starts straight away; otherwise ask.
    private func detectGymAndStart() async {
        isLocating = true
        let fix = await LocationService.shared.currentFix()
        isLocating = false
        switch GymEditing.detect(fix, in: context) {
        case .matched(let gymID):
            begin(at: GymEditing.gym(gymID, in: context))
        case .newGym(let location):
            gymPrompt = .newGym(location)
        case .pickGym:
            gymPrompt = .noLocation
        case .noGym:
            begin(at: nil)
        }
    }

    private func startWithChosenGym() {
        guard let choice = gymChoice else { return }
        gymChoice = nil
        switch choice {
        case .existing(let gym):
            begin(at: gym)
        case .new(let name, let location):
            begin(at: GymEditing.createGym(named: name, at: location, in: context))
        case .noGym:
            begin(at: nil)
        }
    }

    /// Starts the next day of the active split. The split may have changed while locating.
    private func begin(at gym: Gym?) {
        guard inProgress.isEmpty, let split = activeSplits.first, let day = SplitEditing.nextDay(of: split) else { return }
        var rng = SystemRandomNumberGenerator()
        presented = WorkoutFlow.start(day: day, of: split, gym: gym, in: context, using: &rng)
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private func resumeDetail(_ session: WorkoutSession) -> String {
        let sets = session.entries.reduce(0) { $0 + $1.sets.count }
        let started = "Started \(session.startedAt.formatted(date: .omitted, time: .shortened))"
        return sets == 0 ? started : "\(started) · \(sets) \(sets == 1 ? "set" : "sets") logged"
    }

    private func discardIfAsked() {
        guard let session = discarding else { return }
        discarding = nil
        WorkoutFlow.discard(session, in: context)
    }
}

#Preview {
    WorkoutHomeView()
        .modelContainer(PreviewData.container)
}
