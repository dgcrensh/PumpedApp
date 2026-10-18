#if DEBUG
import SwiftData
import SwiftUI

/// Settings → Debug, only in debug builds: fills the store with fake history and clears it again.
struct DebugMenuView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [WorkoutSession]
    @State private var isWorking = false
    @State private var isConfirmingRemove = false
    @State private var message: String?

    private var generatedCount: Int { sessions.filter { $0.id.hasPrefix(DebugHistory.idPrefix) }.count }

    var body: some View {
        List {
            Section {
                Button("Generate 6 months of history") { generate() }
                    .disabled(isWorking)
                if generatedCount > 0 {
                    Button("Remove generated history", role: .destructive) { isConfirmingRemove = true }
                        .disabled(isWorking)
                }
            } header: {
                Text("Fake history")
            } footer: {
                Text("About four workouts a week over the active split's days (or push, pull, legs), picked by the real selection weighting. Real workouts are left alone. Generated workouts: \(generatedCount).")
            }
            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove generated history?", isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button("Remove \(generatedCount) workouts", role: .destructive) {
                let removed = DebugHistory.removeGenerated(in: context)
                message = "Removed \(removed) generated workouts."
            }
        }
    }

    private func generate() {
        isWorking = true
        var rng = SystemRandomNumberGenerator()
        let added = DebugHistory.generate(in: context, using: &rng)
        message = "Added \(added) workouts."
        isWorking = false
    }
}
#endif
