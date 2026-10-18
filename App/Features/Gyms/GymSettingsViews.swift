import SwiftData
import SwiftUI

/// Settings → Gyms (spec §8): every saved gym, with how much is marked unavailable at each.
struct GymListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Gym.name) private var gyms: [Gym]

    var body: some View {
        List {
            ForEach(gyms) { gym in
                NavigationLink {
                    GymDetailView(gym: gym)
                } label: {
                    LabeledContent(gym.name, value: unavailableSummary(gym))
                }
            }
            .onDelete { offsets in
                for gym in offsets.map({ gyms[$0] }) { GymEditing.delete(gym, in: context) }
            }
        }
        .overlay {
            if gyms.isEmpty {
                ContentUnavailableView(
                    "No gyms yet",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Start a workout and Pumped offers to save the gym you're at.")
                )
            }
        }
        .navigationTitle("Gyms")
    }

    private func unavailableSummary(_ gym: Gym) -> String {
        let count = GymEditing.unavailableEquipment(at: gym).count
        return count == 0 ? "" : "\(count) unavailable"
    }
}

/// One gym: rename it, see and clear its unavailable equipment, or delete it.
struct GymDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let gym: Gym

    @State private var name = ""
    @State private var isConfirmingDelete = false
    /// Set once the gym is deleted, so nothing reads it while the view goes away.
    @State private var isDeleted = false

    var body: some View {
        if isDeleted {
            Color.clear
        } else {
            form
        }
    }

    private var form: some View {
        let unavailable = GymEditing.unavailableEquipment(at: gym)
        return Form {
            Section("Name") {
                TextField("Gym name", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { GymEditing.rename(gym, to: name, in: context) }
                    .accessibilityIdentifier("gym-name")
            }
            Section {
                if unavailable.isEmpty {
                    Text("Nothing marked unavailable.")
                        .foregroundStyle(.secondary)
                }
                ForEach(unavailable) { item in
                    LabeledContent(item.name) {
                        Text("until \(item.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    }
                    .swipeActions {
                        Button("Clear") { GymEditing.clear(item.row, in: context) }
                            .tint(.blue)
                    }
                }
                if !unavailable.isEmpty {
                    Button("Clear all") { GymEditing.clearAll(at: gym, in: context) }
                }
            } header: {
                Text("Unavailable equipment")
            } footer: {
                Text("Swiping a card down marks its equipment unavailable here for 7 days. Swipe a row left to clear it sooner.")
            }
            Section {
                Button("Delete gym", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = gym.name }
        .onDisappear {
            guard !isDeleted else { return }
            GymEditing.rename(gym, to: name, in: context)
        }
        .confirmationDialog("Delete \(gym.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete gym", role: .destructive) {
                isDeleted = true
                dismiss()
                GymEditing.delete(gym, in: context)
            }
        } message: {
            Text("Past workouts keep their sets. Next time you train here, Pumped asks you to name it again.")
        }
    }
}
