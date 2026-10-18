import SwiftData
import SwiftUI

/// Stretch sequences, defaults first. Defaults are read-only but can be duplicated; custom ones are editable.
struct StretchSequenceListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StretchSequence.name) private var sequences: [StretchSequence]
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        let defaults = sequences.filter(\.isDefault)
        let custom = sequences.filter { !$0.isDefault }
        List {
            if !defaults.isEmpty {
                Section("Default") {
                    ForEach(defaults) { sequence in
                        NavigationLink {
                            StretchSequenceDetailView(sequence: sequence)
                        } label: {
                            SequenceRow(sequence: sequence)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Duplicate") { SplitEditing.duplicateSequence(sequence, in: context) }
                                .tint(.blue)
                        }
                    }
                }
            }
            Section {
                ForEach(custom) { sequence in
                    NavigationLink {
                        StretchSequenceEditorView(sequence: sequence)
                    } label: {
                        SequenceRow(sequence: sequence)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { SplitEditing.deleteSequence(custom[index], in: context) }
                }
                Button {
                    newName = ""
                    isNaming = true
                } label: {
                    Label("New sequence", systemImage: "plus")
                }
            } header: {
                Text("Custom")
            } footer: {
                Text("Duplicate a default sequence to customize it.")
            }
        }
        .navigationTitle("Stretch sequences")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New sequence", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                SplitEditing.createSequence(named: name.isEmpty ? "My stretches" : name, in: context)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct SequenceRow: View {
    let sequence: StretchSequence

    var body: some View {
        LabeledContent(sequence.name, value: "\(sequence.items.count) stretches")
    }
}

/// Read-only view of a default sequence, with a Duplicate action.
struct StretchSequenceDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let sequence: StretchSequence

    var body: some View {
        let items = sequence.orderedItems
        List {
            Section {
                ForEach(items) { item in
                    LabeledContent(item.stretch?.name ?? "Missing stretch", value: formatDuration(item.durationSec))
                }
            } footer: {
                Text("Total \(formatDuration(items.reduce(0) { $0 + $1.durationSec }))")
            }
        }
        .navigationTitle(sequence.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if sequence.isDefault {
                Button("Duplicate") {
                    SplitEditing.duplicateSequence(sequence, in: context)
                    dismiss()
                }
            }
        }
    }
}

/// Edits a user-defined sequence: name, stretches, hold durations and order.
struct StretchSequenceEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var sequence: StretchSequence
    @State private var isPickingStretch = false

    var body: some View {
        let items = sequence.orderedItems
        List {
            Section("Name") {
                TextField("Sequence name", text: $sequence.name)
            }
            Section {
                ForEach(items) { item in
                    StretchItemRow(item: item)
                }
                .onDelete { SplitEditing.deleteStretches(at: $0, from: sequence, in: context) }
                .onMove { SplitEditing.moveStretches(of: sequence, fromOffsets: $0, toOffset: $1) }

                Button {
                    isPickingStretch = true
                } label: {
                    Label("Add stretch", systemImage: "plus")
                }
            } header: {
                Text("Stretches")
            } footer: {
                Text("Total \(formatDuration(items.reduce(0) { $0 + $1.durationSec }))")
            }
        }
        .navigationTitle(sequence.name.isEmpty ? "Sequence" : sequence.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty { EditButton() }
        }
        .sheet(isPresented: $isPickingStretch) {
            StretchPicker { stretch in
                SplitEditing.addStretch(stretch, to: sequence, in: context)
            }
        }
    }
}

private struct StretchItemRow: View {
    @Bindable var item: StretchItem

    var body: some View {
        Stepper(value: $item.durationSec, in: 5...600, step: 5) {
            LabeledContent(item.stretch?.name ?? "Missing stretch", value: formatDuration(item.durationSec))
        }
    }
}

/// Sheet listing every stretch with its default hold.
private struct StretchPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Stretch.name) private var stretches: [Stretch]
    let onPick: (Stretch) -> Void

    var body: some View {
        NavigationStack {
            List(stretches) { stretch in
                Button {
                    onPick(stretch)
                    dismiss()
                } label: {
                    LabeledContent(stretch.name, value: formatDuration(stretch.defaultDurationSec))
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Add stretch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        StretchSequenceListView()
    }
    .modelContainer(PreviewData.container)
}
