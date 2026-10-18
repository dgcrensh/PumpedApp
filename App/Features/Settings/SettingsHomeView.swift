import SwiftData
import SwiftUI

struct SettingsHomeView: View {
    @Query private var movementTypes: [MovementType]
    @Query private var exercises: [Exercise]
    @Query private var cardioOptions: [CardioOption]
    @Query private var stretches: [Stretch]
    @Query private var stretchSequences: [StretchSequence]
    @Query private var seedState: [SeedState]
    @Query private var gyms: [Gym]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        LabeledContent("Exercises", value: "\(exercises.count)")
                    }
                    NavigationLink {
                        CardioListView()
                    } label: {
                        LabeledContent("Cardio", value: "\(cardioOptions.count)")
                    }
                    NavigationLink {
                        StretchListView()
                    } label: {
                        LabeledContent("Stretches", value: "\(stretches.count)")
                    }
                    NavigationLink {
                        StretchSequenceListView()
                    } label: {
                        LabeledContent("Stretch sequences", value: "\(stretchSequences.count)")
                    }
                    LabeledContent("Movement types", value: "\(movementTypes.count)")
                    LabeledContent("Seed version", value: seedState.first.map { "\($0.appliedVersion)" } ?? "Not imported")
                } header: {
                    Text("Exercise library")
                }
                Section("Workout") {
                    NavigationLink("Rest timers") {
                        RestTimerSettingsView()
                    }
                    NavigationLink {
                        GymListView()
                    } label: {
                        LabeledContent("Gyms", value: "\(gyms.count)")
                    }
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
