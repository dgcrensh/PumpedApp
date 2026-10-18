import SwiftData
import SwiftUI

/// Read-only list of stretches with their default hold.
struct StretchListView: View {
    @Query(sort: \Stretch.name) private var stretches: [Stretch]

    var body: some View {
        List(stretches) { stretch in
            LabeledContent(stretch.name, value: formatDuration(stretch.defaultDurationSec))
        }
        .navigationTitle("Stretches")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Stretch sequences, defaults first.
struct StretchSequenceListView: View {
    @Query(sort: \StretchSequence.name) private var sequences: [StretchSequence]

    var body: some View {
        List {
            sequenceSection("Default", sequences.filter(\.isDefault))
            sequenceSection("Custom", sequences.filter { !$0.isDefault })
        }
        .navigationTitle("Stretch sequences")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func sequenceSection(_ title: String, _ rows: [StretchSequence]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { sequence in
                    NavigationLink {
                        StretchSequenceDetailView(sequence: sequence)
                    } label: {
                        LabeledContent(sequence.name, value: "\(sequence.items.count) stretches")
                    }
                }
            }
        }
    }
}

struct StretchSequenceDetailView: View {
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
    }
}

/// Read-only list of warmup cardio options.
struct CardioListView: View {
    @Query(sort: \CardioOption.name) private var options: [CardioOption]

    var body: some View {
        List(options) { Text($0.name) }
            .navigationTitle("Cardio")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// "0:30", "5:15".
private func formatDuration(_ seconds: Int) -> String {
    Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
}

#Preview {
    NavigationStack {
        StretchSequenceListView()
    }
    .modelContainer(PreviewData.container)
}
