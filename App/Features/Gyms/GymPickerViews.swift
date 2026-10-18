import PumpedCore
import SwiftData
import SwiftUI

/// The gym a workout starts or continues at.
enum GymChoice {
    case existing(Gym)
    case new(name: String, location: Coordinate)
    case noGym
}

/// Shown at workout start when location doesn't match a known gym (spec §8): name the new gym,
/// pick a saved one, or train with no gym.
struct GymPromptSheet: View {
    enum Reason: Identifiable {
        /// Somewhere new; these coordinates are saved with the gym.
        case newGym(Coordinate)
        /// Location was off or didn't come back in time.
        case noLocation

        var id: String {
            switch self {
            case .newGym(let location): "new-\(location.latitude),\(location.longitude)"
            case .noLocation: "no-location"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Gym.name) private var gyms: [Gym]
    let reason: Reason
    let onChoose: (GymChoice) -> Void

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                if case .newGym(let location) = reason {
                    Section {
                        TextField("Gym name", text: $name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit { saveNewGym(at: location) }
                            .accessibilityIdentifier("new-gym-name")
                        Button("Save gym and start") { saveNewGym(at: location) }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    } header: {
                        Text("New gym? Name it")
                    } footer: {
                        Text("Pumped remembers this spot and picks the gym for you next time.")
                    }
                }
                if !gyms.isEmpty {
                    Section {
                        ForEach(gyms) { gym in
                            Button(gym.name) { choose(.existing(gym)) }
                        }
                    } header: {
                        Text(reason.isNewGym ? "Or pick a saved gym" : "Pick your gym")
                    } footer: {
                        if !reason.isNewGym {
                            Text("Couldn't get your location, so pick where you're training.")
                        }
                    }
                }
                Section {
                    Button("No gym") { choose(.noGym) }
                } footer: {
                    Text("With no gym, every exercise is available and swiping down doesn't remember anything.")
                }
            }
            .navigationTitle("Where are you training?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveNewGym(at location: Coordinate) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        choose(.new(name: name, location: location))
    }

    private func choose(_ choice: GymChoice) {
        dismiss()
        onChoose(choice)
    }
}

private extension GymPromptSheet.Reason {
    var isNewGym: Bool {
        if case .newGym = self { return true }
        return false
    }
}

/// Tapping the gym on the workout header: switch to another saved gym, or no gym.
struct ChangeGymSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Gym.name) private var gyms: [Gym]
    let session: WorkoutSession

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(gyms) { gym in
                        row(gym.name, selected: session.gym === gym) { pick(gym) }
                    }
                    row("No gym", selected: session.gym == nil) { pick(nil) }
                } footer: {
                    Text("Cards from here on skip the equipment that's unavailable at this gym.")
                }
            }
            .navigationTitle("Change gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pick(_ gym: Gym?) {
        GymEditing.changeGym(of: session, to: gym, in: context)
        dismiss()
    }
}
