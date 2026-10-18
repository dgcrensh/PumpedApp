import SwiftUI

struct SplitsHomeView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No splits yet",
                systemImage: "list.bullet.rectangle",
                description: Text("The split editor arrives in a later milestone.")
            )
            .navigationTitle("Splits")
        }
    }
}
