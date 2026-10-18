import SwiftData
import SwiftUI

/// Workout tab (spec §10): the next split day with Start, or Resume for a workout in progress.
struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var inProgress: [WorkoutSession]
    @Query(filter: #Predicate<Split> { $0.isActive }) private var activeSplits: [Split]
    @Query(sort: \Gym.name) private var gyms: [Gym]

    @State private var gymID: String?
    @State private var presented: WorkoutSession?
    @State private var discarding: WorkoutSession?
    @State private var didAutoResume = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Workout")
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
            Section("Movements") {
                if day.slots.isEmpty {
                    Text("No movements yet. Add some in the Splits tab.")
                        .foregroundStyle(.secondary)
                }
                ForEach(day.orderedSlots) { slot in
                    Text(slot.movementType?.name ?? "Unknown movement")
                }
            }
            Section {
                Picker("Gym", selection: $gymID) {
                    Text("No gym").tag(String?.none)
                    ForEach(gyms) { gym in
                        Text(gym.name).tag(Optional(gym.id))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bigButton("Start workout") {
                // The rest timer notifies at zero; ask the first time a workout starts.
                Task { await RestTimerService.requestPermission() }
                var rng = SystemRandomNumberGenerator()
                presented = WorkoutFlow.start(
                    day: day,
                    of: split,
                    gym: gyms.first { $0.id == gymID },
                    in: context,
                    using: &rng
                )
            }
        }
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
