import PumpedCore
import SwiftUI

/// The rest countdown on the card (spec §6.2), with Skip and +30s and a haptic at zero. Shows
/// nothing while no rest is running.
struct RestTimerView: View {
    @Environment(\.modelContext) private var context
    let session: WorkoutSession

    @State private var restsFinished = 0

    var body: some View {
        let timer = WorkoutFlow.restTimer(of: session)
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            if timer.isRunning(at: timeline.date) {
                countdown(timer.displaySeconds(at: timeline.date))
            }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: restsFinished)
        .task(id: session.restTimerEndsAt) {
            guard let endsAt = session.restTimerEndsAt, endsAt > .now else { return }
            try? await Task.sleep(for: .seconds(endsAt.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            restsFinished += 1
        }
    }

    private func countdown(_ seconds: Int) -> some View {
        HStack(spacing: 12) {
            Label {
                Text(CountdownText.format(seconds))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            } icon: {
                Image(systemName: "timer")
                    .foregroundStyle(.tint)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rest, \(seconds) seconds left")
            .accessibilityIdentifier("rest-timer")
            Spacer(minLength: 0)
            Button("+30s") {
                WorkoutFlow.extendRest(in: session, context: context)
                RestTimerService.sync(session)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add 30 seconds")
            Button("Skip") {
                WorkoutFlow.skipRest(in: session, context: context)
                RestTimerService.sync(session)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Skip rest")
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
