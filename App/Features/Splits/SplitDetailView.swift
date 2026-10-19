import PumpedCore
import SwiftData
import SwiftUI

/// Edits one split: its name, whether it's active, where the cycle stands, and its days.
struct SplitDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var split: Split
    @State private var isNamingDay = false
    @State private var newDayName = ""

    var body: some View {
        let days = split.orderedDays
        List {
            Section("Name") {
                TextField("Split name", text: $split.name)
            }

            Section {
                if let nextUp = SplitCycleText.nextUp(for: split) {
                    Text(nextUp)
                        .font(NightShift.display(.title3, weight: .bold))
                        .foregroundStyle(NightShift.accent)
                    Picker("Next day", selection: nextDayIndex) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                            Text(day.name).tag(index)
                        }
                    }
                } else {
                    Text("Add a day to start the cycle.")
                        .foregroundStyle(.secondary)
                }
                if split.isActive {
                    Label("Active split", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NightShift.accent)
                } else {
                    Button("Make active") { SplitEditing.setActive(split, in: context) }
                }
            } header: {
                Text("Cycle")
            } footer: {
                Text("Finishing a workout moves to the next day. Pick a different next day to skip or repeat one.")
            }

            Section("Days") {
                let next = SplitCycle(dayCount: days.count, nextDayIndex: split.nextDayIndex).nextDayIndex
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    NavigationLink {
                        SplitDayEditorView(day: day)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            NightShiftLabel(
                                text: index == next ? "Next up" : "Day \(index + 1)",
                                color: index == next ? NightShift.accent : NightShift.muted
                            )
                            Text(day.name)
                                .font(NightShift.display(.title2))
                                .textCase(.uppercase)
                            Text(daySummary(day))
                                .font(.caption)
                                .foregroundStyle(NightShift.muted)
                        }
                        .padding(.vertical, 4)
                        // Name first, so the row reads (and is found) by its day.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.name), \(index == next ? "next up" : "day \(index + 1)"), \(daySummary(day))")
                    }
                    .listRowBackground(index == next ? NightShift.raised : NightShift.surface)
                }
                .onDelete { SplitEditing.deleteDays(at: $0, from: split, in: context) }
                .onMove { SplitEditing.moveDays(of: split, fromOffsets: $0, toOffset: $1) }

                Button {
                    newDayName = ""
                    isNamingDay = true
                } label: {
                    Label("Add day", systemImage: "plus")
                }
            }
        }
        .nightShiftList()
        .navigationTitle(split.name.isEmpty ? "Split" : split.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !days.isEmpty { EditButton() }
        }
        .alert("New day", isPresented: $isNamingDay) {
            TextField("Name, e.g. Push", text: $newDayName)
            Button("Add") {
                let name = newDayName.trimmingCharacters(in: .whitespacesAndNewlines)
                SplitEditing.addDay(named: name.isEmpty ? "Day \(days.count + 1)" : name, to: split, in: context)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var nextDayIndex: Binding<Int> {
        Binding(
            get: { SplitCycle(dayCount: split.days.count, nextDayIndex: split.nextDayIndex).nextDayIndex },
            set: { index in
                let days = split.orderedDays
                if days.indices.contains(index) { SplitEditing.setNextDay(days[index], of: split) }
            }
        )
    }

    private func daySummary(_ day: SplitDay) -> String {
        let names = day.orderedSlots.compactMap { $0.movementType?.name }
        return names.isEmpty ? "No movements yet" : names.joined(separator: ", ")
    }
}
