import SwiftUI

/// The four top-level tabs (spec §10).
struct RootTabView: View {
    var body: some View {
        TabView {
            WorkoutHomeView()
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
            HistoryHomeView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SplitsHomeView()
                .tabItem { Label("Splits", systemImage: "list.bullet.rectangle") }
            SettingsHomeView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
