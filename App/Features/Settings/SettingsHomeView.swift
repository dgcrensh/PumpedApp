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
    @Query(filter: #Predicate<Exercise> { $0.isHidden }) private var hidden: [Exercise]
    @Query(filter: #Predicate<Exercise> { $0.isLiked }) private var liked: [Exercise]
    @Query(filter: #Predicate<Exercise> { $0.isCustom }) private var customExercises: [Exercise]
    @Query(filter: #Predicate<Stretch> { $0.isCustom }) private var customStretches: [Stretch]

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
                Section("Your exercises") {
                    NavigationLink {
                        LikedExercisesView()
                    } label: {
                        LabeledContent("Liked exercises", value: "\(liked.count)")
                    }
                    NavigationLink {
                        HiddenExercisesView()
                    } label: {
                        LabeledContent("Hidden exercises", value: "\(hidden.count)")
                    }
                    NavigationLink {
                        CustomExercisesView()
                    } label: {
                        LabeledContent("Custom exercises", value: "\(customExercises.count)")
                    }
                    NavigationLink {
                        CustomStretchesView()
                    } label: {
                        LabeledContent("Custom stretches", value: "\(customStretches.count)")
                    }
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
                #if DEBUG
                Section {
                    NavigationLink("Debug") {
                        DebugMenuView()
                    }
                } footer: {
                    Text("Only in debug builds.")
                }
                #endif
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsHomeView()
        .modelContainer(PreviewData.container)
}
