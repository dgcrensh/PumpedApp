import SwiftUI

struct WorkoutHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No workout yet",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Starting and resuming workouts arrives in a later milestone.")
            )
            .navigationTitle("Workout")
        }
    }
}
