import SwiftData
import SwiftUI

/// Edits one split day: its ordered movement slots, cool-down stretch sequence and default warmup cardio.
struct SplitDayEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var day: SplitDay
    @Query(sort: \StretchSequence.name) private var sequences: [StretchSequence]
    @Query(sort: \CardioOption.name) private var cardioOptions: [CardioOption]
    @State private var isPickingMovement = false

    var body: some View {
        let slots = day.orderedSlots
        List {
            Section("Name") {
                TextField("Day name", text: $day.name)
            }

            Section {
                if slots.isEmpty {
                    Text("No movements yet. A workout of this day has nothing to lift until you add some.")
                        .foregroundStyle(NightShift.muted)
                }
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", index + 1))
                            .font(NightShift.display(.body, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(NightShift.faint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.movementType?.name ?? "Missing movement")
                                .font(.body.weight(.semibold))
                            if let muscles = slot.movementType?.primaryMuscles, !muscles.isEmpty {
                                Text(MuscleGroupNames.list(muscles))
                                    .font(.caption)
                                    .foregroundStyle(NightShift.muted)
                            }
                        }
                    }
                }
                .onDelete { SplitEditing.deleteSlots(at: $0, from: day, in: context) }
                .onMove { SplitEditing.moveSlots(of: day, fromOffsets: $0, toOffset: $1) }

                Button {
                    isPickingMovement = true
                } label: {
                    Label("Add movement", systemImage: "plus")
                }
            } header: {
                Text("Movements")
            } footer: {
                Text("Workouts follow this order. Add a movement twice to get two different variations.")
            }

            Section("Cool-down") {
                Picker("Stretch sequence", selection: $day.stretchSequence) {
                    Text("None").tag(StretchSequence?.none)
                    ForEach(sequences) { sequence in
                        Text(sequence.name).tag(StretchSequence?.some(sequence))
                    }
                }
            }

            Section("Warmup") {
                Picker("Default cardio", selection: $day.defaultCardio) {
                    Text("None").tag(CardioOption?.none)
                    ForEach(cardioOptions) { option in
                        Text(option.name).tag(CardioOption?.some(option))
                    }
                }
            }
        }
        .nightShiftList()
        .navigationTitle(day.name.isEmpty ? "Day" : day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !slots.isEmpty { EditButton() }
        }
        .sheet(isPresented: $isPickingMovement) {
            MovementTypePicker { movementType in
                SplitEditing.addSlot(movementType, to: day, in: context)
            }
        }
    }
}

/// Sheet listing every movement type, with its primary muscles.
private struct MovementTypePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MovementType.name) private var movementTypes: [MovementType]
    let onPick: (MovementType) -> Void

    var body: some View {
        NavigationStack {
            List(movementTypes) { movementType in
                Button {
                    onPick(movementType)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movementType.name)
                            .foregroundStyle(.primary)
                        Text(MuscleGroupNames.list(movementType.primaryMuscles))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
