import SwiftUI

/// The cool-down (spec §6.3): the split day's stretches, then finishing the workout.
///
/// A plain list for now; the timed full-screen stretch player replaces it in a later milestone.
struct CooldownView: View {
    @Environment(\.modelContext) private var context
    let session: WorkoutSession
    @Binding var undo: SwipeUndo?
    let onFinish: () -> Void

    var body: some View {
        List {
            if let sequence = session.splitDay?.stretchSequence, !sequence.items.isEmpty {
                Section(sequence.name) {
                    ForEach(sequence.orderedItems) { item in
                        HStack {
                            Text(item.stretch?.name ?? "Stretch")
                            Spacer()
                            Text(Duration.seconds(item.durationSec).formatted(.time(pattern: .minuteSecond)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Section {
                    Text("This day has no stretch sequence.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Finish workout") { finish(cooldownCompleted: true) }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                Button("Skip cool-down") { finish(cooldownCompleted: false) }
                    .frame(maxWidth: .infinity)
            } footer: {
                if !WorkoutFlow.hasLoggedSets(session) {
                    Text("No sets were logged, so the split stays on this day.")
                }
            }
        }
        .navigationTitle("Cool-down")
    }

    private func finish(cooldownCompleted: Bool) {
        undo = nil
        WorkoutFlow.finish(session, cooldownCompleted: cooldownCompleted, in: context)
        onFinish()
    }
}
