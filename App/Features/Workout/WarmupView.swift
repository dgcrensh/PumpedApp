import SwiftData
import SwiftUI

/// The warmup card (spec §6.1): cardio, duration (required) and distance (optional), or skip.
struct WarmupView: View {
    @Environment(\.modelContext) private var context
    let session: WorkoutSession
    @Query(sort: \CardioOption.name) private var cardioOptions: [CardioOption]

    @State private var cardioID: String?
    @State private var minutes = 10
    @State private var distance = ""
    @State private var didPrefill = false

    var body: some View {
        Form {
            Section {
                Picker("Cardio", selection: $cardioID) {
                    ForEach(cardioOptions) { option in
                        Text(option.name).tag(Optional(option.id))
                    }
                }
                Stepper("\(minutes) min", value: $minutes, in: 1...180)
                HStack {
                    Text("Distance")
                    TextField("Optional", text: $distance)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("mi")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Warmup")
            }
            Section {
                Button("Log warmup", action: log)
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                Button("Skip warmup") { WorkoutFlow.skipWarmup(session, in: context) }
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear(perform: prefill)
    }

    private func log() {
        let cardio = cardioOptions.first { $0.id == cardioID }
        let miles = Double(distance.replacingOccurrences(of: ",", with: "."))
        WorkoutFlow.logWarmup(
            cardio: cardio,
            durationSec: minutes * 60,
            distanceMi: miles.flatMap { $0 > 0 ? $0 : nil },
            in: session,
            context: context
        )
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        cardioID = WorkoutFlow.suggestedCardio(for: session, in: context)?.id ?? cardioOptions.first?.id
    }
}
