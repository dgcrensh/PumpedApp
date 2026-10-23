import SwiftData
import SwiftUI

/// Edits one split day: its ordered movement slots, cool-down stretch sequence and default warmup cardio.
struct SplitDayEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var day: SplitDay
    @Query(sort: \StretchSequence.name) private var sequences: [StretchSequence]
    @Query(sort: \CardioOption.name) private var cardioOptions: [CardioOption]
    @State private var isPickingMovement = false
    @State private var pinningSlot: MovementSlot?

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
                    Button {
                        pinningSlot = slot
                    } label: {
                        SlotRow(number: index + 1, slot: slot)
                    }
                    .tint(.primary)
                    .disabled(slot.movementType == nil)
                    .accessibilityHint("Pins this movement to one exercise.")
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
                Text("Workouts follow this order. Add a movement twice to get two different variations. Tap a movement to pin it to one exercise.")
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
        .sheet(item: $pinningSlot) { slot in
            PinPicker(slot: slot)
        }
    }
}

/// A movement slot: its number, movement, primary muscles, and the exercise it's pinned to.
private struct SlotRow: View {
    let number: Int
    let slot: MovementSlot

    var body: some View {
        HStack(spacing: 14) {
            Text(String(format: "%02d", number))
                .font(NightShift.display(.body, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(NightShift.faint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.movementType?.name ?? "Missing movement")
                    .font(.body.weight(.semibold))
                if let pinned = slot.pinnedExercise {
                    Label(pinned.isHidden ? "\(pinned.name) (hidden, so not used)" : pinned.name, systemImage: "pin.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(pinned.isHidden ? NightShift.muted : NightShift.accent)
                        .accessibilityLabel("Pinned to \(pinned.name)\(pinned.isHidden ? ", hidden, so not used" : "")")
                } else if let muscles = slot.movementType?.primaryMuscles, !muscles.isEmpty {
                    Text(MuscleGroupNames.list(muscles))
                        .font(.caption)
                        .foregroundStyle(NightShift.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Sheet for pinning a slot to one of its movement type's exercises, or letting workouts rotate.
private struct PinPicker: View {
    @Environment(\.dismiss) private var dismiss
    let slot: MovementSlot

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Rotate variations", detail: nil, isOn: slot.pinnedExercise == nil) {
                        SplitEditing.setPin(nil, on: slot)
                    }
                } footer: {
                    Text("Workouts pick a variation for you, favoring ones you like and do often.")
                }

                Section {
                    ForEach(SplitEditing.pinCandidates(for: slot)) { exercise in
                        row(exercise.name, detail: equipmentText(exercise), isOn: slot.pinnedExercise === exercise) {
                            SplitEditing.setPin(exercise, on: slot)
                        }
                    }
                } header: {
                    Text("Always use")
                } footer: {
                    Text("If its equipment is marked unavailable at your gym, or you hide it, workouts pick another variation that day.")
                }
            }
            .navigationTitle("Pin \(slot.movementType?.name ?? "movement")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, detail: String?, isOn: Bool, choose: @escaping () -> Void) -> some View {
        Button {
            choose()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func equipmentText(_ exercise: Exercise) -> String {
        let names = exercise.equipment.map(\.name).sorted()
        return names.isEmpty ? "Bodyweight" : names.joined(separator: ", ")
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
