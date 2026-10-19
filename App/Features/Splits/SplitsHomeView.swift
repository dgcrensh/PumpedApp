import PumpedCore
import SwiftData
import SwiftUI

/// Splits tab: every split, which one is active, and the stretch sequences (spec §5).
struct SplitsHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Split.createdAt) private var splits: [Split]
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if !splits.isEmpty {
                    Section("Splits") {
                        ForEach(splits) { split in
                            NavigationLink {
                                SplitDetailView(split: split)
                            } label: {
                                SplitRow(split: split)
                            }
                            .swipeActions(edge: .leading) {
                                if !split.isActive {
                                    Button("Set active") { SplitEditing.setActive(split, in: context) }
                                        .tint(.green)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { SplitEditing.deleteSplit(splits[index], in: context) }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        StretchSequenceListView()
                    } label: {
                        Label("Stretch sequences", systemImage: "figure.flexibility")
                    }
                }
            }
            .overlay {
                if splits.isEmpty {
                    ContentUnavailableView {
                        Label("No splits yet", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("A split is a cycle of days, like Push, Pull, Legs.")
                    } actions: {
                        Button("Create a split") { startNaming() }
                            .buttonStyle(.nightShiftPrimaryInline)
                    }
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Splits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { startNaming() } label: { Label("New split", systemImage: "plus") }
                }
            }
            .alert("New split", isPresented: $isNaming) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    SplitEditing.createSplit(named: name.isEmpty ? "Split \(splits.count + 1)" : name, in: context)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func startNaming() {
        newName = ""
        isNaming = true
    }
}

private struct SplitRow: View {
    let split: Split

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(split.name)
                if split.isActive {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2), in: Capsule())
                }
            }
            Text(SplitCycleText.summary(for: split))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Wording for where a split's cycle stands.
@MainActor
enum SplitCycleText {
    /// "Next up: Pull, day 2 of 3", or nil for a split with no days.
    static func nextUp(for split: Split) -> String? {
        let days = split.orderedDays
        let cycle = SplitCycle(dayCount: days.count, nextDayIndex: split.nextDayIndex)
        guard let position = cycle.position else { return nil }
        return "Next up: \(days[cycle.nextDayIndex].name), day \(position) of \(days.count)"
    }

    static func summary(for split: Split) -> String {
        nextUp(for: split) ?? "No days yet"
    }
}

#Preview {
    SplitsHomeView()
        .modelContainer(PreviewData.container)
}
