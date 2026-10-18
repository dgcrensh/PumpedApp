import PumpedCore
import SwiftUI

/// The end-of-workout summary (spec §6.4): duration, exercises, sets, volume and PRs hit.
struct WorkoutSummaryView: View {
    @Environment(\.modelContext) private var context
    let session: WorkoutSession
    let onDone: () -> Void

    @State private var summary: WorkoutSummary?

    var body: some View {
        List {
            if let summary {
                Section {
                    LabeledContent("Duration", value: WorkoutSummary.durationText(summary.duration))
                    LabeledContent("Exercises", value: "\(summary.exerciseNames.count)")
                    LabeledContent("Sets", value: "\(summary.setCount)")
                    LabeledContent("Volume", value: "\(summary.volumeLb.formatted(.number.precision(.fractionLength(0)))) lb")
                } footer: {
                    if summary.setCount == 0 {
                        Text("No sets were logged, so the split stays on this day.")
                    } else if let next = nextDayName {
                        Text("Next up: \(next).")
                    }
                }
                if !summary.prs.isEmpty {
                    Section("PRs") {
                        ForEach(Array(summary.prs.enumerated()), id: \.offset) { _, hit in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.exerciseName)
                                    Text(hit.record.summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "trophy.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                if !summary.exerciseNames.isEmpty {
                    Section("Exercises") {
                        ForEach(Array(summary.exerciseNames.enumerated()), id: \.offset) { _, name in
                            Text(name)
                        }
                    }
                }
            }
        }
        .navigationTitle("Workout complete")
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .task { summary = WorkoutFlow.summary(of: session, in: context) }
    }

    private var nextDayName: String? {
        session.split.flatMap { SplitEditing.nextDay(of: $0) }?.name
    }
}
