import SwiftUI

struct HistoryHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No workouts logged",
                systemImage: "clock.arrow.circlepath",
                description: Text("Finished workouts, progress charts and PRs will show up here.")
            )
            .navigationTitle("History")
        }
    }
}
