import SwiftData
import SwiftUI

struct SettingsHomeView: View {
    @Query private var movementTypes: [MovementType]
    @Query private var exercises: [Exercise]
    @Query private var stretches: [Stretch]
    @Query private var stretchSequences: [StretchSequence]
    @Query private var seedState: [SeedState]

    var body: some View {
        NavigationStack {
            List {
                Section("Exercise library") {
                    LabeledContent("Movement types", value: "\(movementTypes.count)")
                    LabeledContent("Exercises", value: "\(exercises.count)")
                    LabeledContent("Stretches", value: "\(stretches.count)")
                    LabeledContent("Stretch sequences", value: "\(stretchSequences.count)")
                    LabeledContent("Seed version", value: seedState.first.map { "\($0.appliedVersion)" } ?? "Not imported")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsHomeView()
        .modelContainer(PreviewData.container)
}
