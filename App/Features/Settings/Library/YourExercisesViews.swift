import PumpedCore
import SwiftData
import SwiftUI

/// Settings → Hidden exercises: everything "Never show me this" took out, with Unhide.
struct HiddenExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isHidden }, sort: \Exercise.name) private var exercises: [Exercise]

    var body: some View {
        List {
            if !exercises.isEmpty {
                Section {
                    ForEach(exercises) { exercise in
                        HStack {
                            ExerciseNameRow(exercise: exercise)
                            Spacer()
                            Button("Unhide") { LibraryEditing.setHidden(exercise, false, in: context) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Unhide \(exercise.name)")
                        }
                    }
                } footer: {
                    Text("Hidden exercises are never picked for a workout. Unhide one to bring it back.")
                }
            }
        }
        .overlay {
            if exercises.isEmpty {
                ContentUnavailableView(
                    "Nothing hidden",
                    systemImage: "eye.slash",
                    description: Text("Choose \"Never show me this\" in a card's menu to stop an exercise coming up.")
                )
            }
        }
        .navigationTitle("Hidden exercises")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings → Liked exercises: the ones picked more often, with Unlike.
struct LikedExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isLiked }, sort: \Exercise.name) private var exercises: [Exercise]

    var body: some View {
        List {
            if !exercises.isEmpty {
                Section {
                    ForEach(exercises) { exercise in
                        HStack {
                            ExerciseNameRow(exercise: exercise)
                            Spacer()
                            Button("Unlike") { LibraryEditing.setLiked(exercise, false, in: context) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Unlike \(exercise.name)")
                        }
                    }
                } footer: {
                    Text("Liked exercises come up more often in workouts.")
                }
            }
        }
        .overlay {
            if exercises.isEmpty {
                ContentUnavailableView(
                    "No liked exercises",
                    systemImage: "heart",
                    description: Text("Swipe a card up during a workout to like it.")
                )
            }
        }
        .navigationTitle("Liked exercises")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings → Custom exercises: create, edit and delete your own exercises.
struct CustomExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isCustom }, sort: \Exercise.name) private var exercises: [Exercise]
    @State private var editing: EditingExercise?
    @State private var undeletable: Exercise?

    /// The sheet's subject: nil `exercise` means a new one.
    struct EditingExercise: Identifiable {
        let id = UUID()
        let exercise: Exercise?
    }

    var body: some View {
        List {
            ForEach(exercises) { exercise in
                Button {
                    editing = EditingExercise(exercise: exercise)
                } label: {
                    ExerciseNameRow(exercise: exercise)
                }
                .tint(.primary)
            }
            .onDelete { offsets in
                for exercise in offsets.map({ exercises[$0] }) {
                    let deleted = LibraryEditing.deleteExercise(exercise, in: context)
                    if !deleted { undeletable = exercise }
                }
            }
        }
        .overlay {
            if exercises.isEmpty {
                ContentUnavailableView {
                    Label("No custom exercises", systemImage: "dumbbell")
                } description: {
                    Text("Add an exercise the library is missing. Workouts pick it like any other.")
                } actions: {
                    Button("Add exercise") { editing = EditingExercise(exercise: nil) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Custom exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = EditingExercise(exercise: nil) } label: { Label("New exercise", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { item in
            CustomExerciseEditor(exercise: item.exercise)
        }
        .alert(
            "Can't delete \(undeletable?.name ?? "this exercise")",
            isPresented: Binding(get: { undeletable != nil }, set: { if !$0 { undeletable = nil } })
        ) {
            if let exercise = undeletable, !exercise.isHidden {
                Button("Hide it") { LibraryEditing.setHidden(exercise, true, in: context) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("It's in your workout history. Hide it to stop it coming up.")
        }
    }
}

/// The form for a new or existing custom exercise.
struct CustomExerciseEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MovementType.name) private var movementTypes: [MovementType]
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    let exercise: Exercise?

    @State private var draft = LibraryEditing.ExerciseDraft()

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Exercise name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("custom-exercise-name")
                }
                Section {
                    Picker("Movement", selection: movementBinding) {
                        Text("Choose…").tag(String?.none)
                        ForEach(movementTypes) { movementType in
                            Text(movementType.name).tag(String?.some(movementType.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("Type", selection: $draft.exerciseType) {
                        ForEach(ExerciseType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                } footer: {
                    Text("Workouts use it for slots of this movement. The type sets the rest timer.")
                }
                Section {
                    ForEach(equipment) { item in
                        checkRow(item.name, isOn: draft.equipmentIDs.contains(item.id)) {
                            draft.equipmentIDs.formSymmetricDifference([item.id])
                        }
                    }
                } header: {
                    Text("Equipment")
                } footer: {
                    Text(draft.equipmentIDs.isEmpty ? "None selected: bodyweight." : "Skipped at a gym where any of these is marked unavailable.")
                }
                Section {
                    ForEach(MuscleGroupNames.all) { muscle in
                        checkRow(muscle.name, isOn: draft.muscles.contains(muscle.id)) {
                            draft.muscles.formSymmetricDifference([muscle.id])
                        }
                    }
                } header: {
                    Text("Muscles")
                } footer: {
                    Text("Used for substitutes and progress. Leave empty to use the movement's muscles.")
                }
            }
            .navigationTitle(exercise == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.isValid)
                }
            }
            .onAppear {
                if let exercise { draft = LibraryEditing.draft(of: exercise) }
            }
        }
    }

    /// Picking a movement fills in its muscles while the muscle list is still the previous default.
    private var movementBinding: Binding<String?> {
        Binding(
            get: { draft.movementTypeID },
            set: { id in
                let previous = muscles(of: draft.movementTypeID)
                if draft.muscles.isEmpty || draft.muscles == previous { draft.muscles = muscles(of: id) }
                draft.movementTypeID = id
            }
        )
    }

    private func muscles(of movementTypeID: String?) -> Set<String> {
        Set(movementTypes.first { $0.id == movementTypeID }?.primaryMuscles ?? [])
    }

    private func checkRow(_ title: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .tint(.primary)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func save() {
        if let exercise {
            LibraryEditing.update(exercise, with: draft, in: context)
        } else {
            LibraryEditing.createExercise(draft, in: context)
        }
        dismiss()
    }
}

/// Settings → Custom stretches: your own stretches for cool-down sequences.
struct CustomStretchesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Stretch> { $0.isCustom }, sort: \Stretch.name) private var stretches: [Stretch]
    @State private var editing: EditingStretch?
    @State private var deleting: Stretch?

    struct EditingStretch: Identifiable {
        let id = UUID()
        let stretch: Stretch?
    }

    var body: some View {
        List {
            ForEach(stretches) { stretch in
                Button {
                    editing = EditingStretch(stretch: stretch)
                } label: {
                    LabeledContent(stretch.name, value: formatDuration(stretch.defaultDurationSec))
                }
                .tint(.primary)
            }
            .onDelete { offsets in deleting = offsets.first.map { stretches[$0] } }
        }
        .overlay {
            if stretches.isEmpty {
                ContentUnavailableView {
                    Label("No custom stretches", systemImage: "figure.flexibility")
                } description: {
                    Text("Add a stretch to use it in your own stretch sequences.")
                } actions: {
                    Button("Add stretch") { editing = EditingStretch(stretch: nil) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Custom stretches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = EditingStretch(stretch: nil) } label: { Label("New stretch", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { item in
            CustomStretchEditor(stretch: item.stretch)
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "stretch")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { stretch in
            Button("Delete stretch", role: .destructive) { LibraryEditing.deleteStretch(stretch, in: context) }
        } message: { stretch in
            let names = LibraryEditing.sequences(using: stretch, in: context).map(\.name)
            Text(names.isEmpty ? "It isn't in any stretch sequence." : "It's also removed from \(names.formatted(.list(type: .and))).")
        }
    }
}

/// The form for a new or existing custom stretch.
struct CustomStretchEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let stretch: Stretch?

    @State private var name = ""
    @State private var durationSec = 30

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Stretch name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("custom-stretch-name")
                }
                Section {
                    Stepper(value: $durationSec, in: LibraryEditing.stretchDurationRange, step: 5) {
                        LabeledContent("Hold", value: formatDuration(durationSec))
                    }
                } footer: {
                    Text("The hold a sequence starts with when you add this stretch. Each sequence can change it.")
                }
            }
            .navigationTitle(stretch == nil ? "New stretch" : "Edit stretch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .onAppear {
                if let stretch {
                    name = stretch.name
                    durationSec = stretch.defaultDurationSec
                }
            }
        }
    }

    private func save() {
        if let stretch {
            LibraryEditing.updateStretch(stretch, name: name, durationSec: durationSec, in: context)
        } else {
            LibraryEditing.createStretch(named: name, durationSec: durationSec, in: context)
        }
        dismiss()
    }
}

/// An exercise's name with its movement type and equipment underneath.
private struct ExerciseNameRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let equipment = exercise.equipment.map(\.name).sorted()
        let parts = [exercise.movementType?.name, equipment.isEmpty ? "Bodyweight" : equipment.joined(separator: ", ")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

#Preview("Custom exercise") {
    CustomExerciseEditor(exercise: nil)
        .modelContainer(PreviewData.container)
}

#Preview("Hidden, dark") {
    NavigationStack {
        HiddenExercisesView()
    }
    .modelContainer(PreviewData.container)
    .preferredColorScheme(.dark)
}
