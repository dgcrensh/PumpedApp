import PumpedCore
import SwiftData
import SwiftUI

/// History tab (spec §9): finished workouts, newest first, with exercise progress and PRs.
struct HistoryHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var workouts: [WorkoutSession]

    @State private var deleting: WorkoutSession?

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "No workouts logged",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finished workouts, progress charts and PRs will show up here.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !workouts.isEmpty {
                    NavigationLink {
                        TrainedExercisesView()
                    } label: {
                        Label("Exercises", systemImage: "chart.xyaxis.line")
                    }
                }
            }
            .historyDestinations()
        }
    }

    private var list: some View {
        List {
            ForEach(workouts) { session in
                NavigationLink(value: session) {
                    WorkoutRow(session: session)
                }
                .accessibilityIdentifier("workout-row")
                .swipeActions {
                    Button("Delete", role: .destructive) { deleting = session }
                }
            }
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { session in
            Button("Delete workout", role: .destructive) {
                HistoryData.delete(session, in: context)
                deleting = nil
            }
        } message: { _ in
            Text("Its sets and PRs are removed from your history.")
        }
    }
}

/// A history row: date, split day, gym and duration.
struct WorkoutRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.splitDay?.name ?? "Workout")
                .font(.headline)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let duration = WorkoutSummary.durationText(session.duration)
        return [session.gym?.name ?? "No gym", duration].joined(separator: " · ")
    }
}

/// Exercises with logged sets, each opening its progress.
struct TrainedExercisesView: View {
    @Environment(\.modelContext) private var context
    @State private var exercises: [Exercise] = []

    var body: some View {
        List(exercises) { exercise in
            NavigationLink(value: exercise) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                    if let movementType = exercise.movementType?.name {
                        Text(movementType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if exercises.isEmpty {
                ContentUnavailableView("No exercises logged", systemImage: "chart.xyaxis.line")
            }
        }
        .navigationTitle("Exercises")
        .onAppear { exercises = HistoryData.trainedExercises(in: context) }
    }
}

extension WorkoutSession {
    /// Time from start to finish, or so far for a workout in progress.
    var duration: TimeInterval {
        max((endedAt ?? .now).timeIntervalSince(startedAt), 0)
    }
}

extension View {
    /// Where history rows and exercise names lead.
    func historyDestinations() -> some View {
        navigationDestination(for: WorkoutSession.self) { WorkoutDetailView(session: $0) }
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
    }
}
