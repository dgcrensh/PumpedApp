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
        HStack(spacing: 10) {
            Label {
                Text(CountdownText.format(seconds))
                    .font(NightShift.display(.title2, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(NightShift.text)
                    .contentTransition(.numericText(countsDown: true))
            } icon: {
                Image(systemName: "timer")
                    .foregroundStyle(NightShift.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rest, \(seconds) seconds left")
            .accessibilityIdentifier("rest-timer")
            Spacer(minLength: 0)
            Button("+30s") {
                WorkoutFlow.extendRest(in: session, context: context)
                RestTimerService.sync(session)
            }
            .buttonStyle(RestButtonStyle())
            .accessibilityLabel("Add 30 seconds")
            Button("Skip") {
                WorkoutFlow.skipRest(in: session, context: context)
                RestTimerService.sync(session)
            }
            .buttonStyle(RestButtonStyle())
            .accessibilityLabel("Skip rest")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(NightShift.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The timer's small +30s and Skip buttons.
private struct RestButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(NightShift.text)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(NightShift.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
