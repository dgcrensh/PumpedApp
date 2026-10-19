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
        .toolbarBackground(NightShift.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .nightShiftTheme()
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
