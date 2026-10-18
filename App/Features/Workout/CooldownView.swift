import PumpedCore
import SwiftUI

/// The cool-down player (spec §6.3): each stretch full screen with a countdown that auto-advances
/// (with a haptic), plus pause, skip and back. Finishing or skipping it completes the workout.
struct CooldownView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    let session: WorkoutSession
    @Binding var undo: SwipeUndo?

    @State private var player: CooldownPlayer?
    @State private var autoAdvances = 0

    private var items: [StretchItem] { session.splitDay?.stretchSequence?.orderedItems ?? [] }

    var body: some View {
        VStack(spacing: 24) {
            if let player {
                TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                    if player.isFinished {
                        done
                    } else {
                        stretch(player, at: timeline.date)
                    }
                }
                .frame(maxHeight: .infinity)
                controls(player)
            } else {
                ContentUnavailableView(
                    "No stretches",
                    systemImage: "figure.cooldown",
                    description: Text("This day has no stretch sequence.")
                )
            }
            finishButtons
        }
        .padding()
        .navigationTitle("Cool-down")
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: autoAdvances)
        .onAppear(perform: load)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { catchUp() }
        }
        .task(id: player) {
            // Sleeps until the current stretch ends, then moves on. Changing the player restarts it.
            guard let endsAt = player?.endsAt else { return }
            try? await Task.sleep(for: .seconds(max(endsAt.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            catchUp()
        }
    }

    // MARK: Pieces

    private func stretch(_ player: CooldownPlayer, at now: Date) -> some View {
        let item = items[safe: player.index]
        let total = TimeInterval(player.durations[player.index])
        return VStack(spacing: 20) {
            Text("Stretch \(player.index + 1) of \(player.durations.count)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(item?.stretch?.name ?? "Stretch")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("stretch-name")
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: total > 0 ? player.remaining(at: now) / total : 0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(CountdownText.format(player.displaySeconds(at: now)))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("\(player.displaySeconds(at: now)) seconds left")
            }
            .frame(width: 240, height: 240)
            if player.isPaused {
                Text("Paused")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            if let next = items[safe: player.index + 1]?.stretch?.name {
                Text("Next: \(next)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Cool-down done")
                .font(.title.bold())
        }
    }

    private func controls(_ player: CooldownPlayer) -> some View {
        HStack(spacing: 40) {
            Button { change { $0.back(at: .now) } } label: {
                Image(systemName: "backward.fill")
            }
            .accessibilityLabel("Previous stretch")
            Button {
                change { player in
                    if player.isPaused { player.resume(at: .now) } else { player.pause(at: .now) }
                }
            } label: {
                Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 44)
            }
            .accessibilityLabel(player.isPaused ? "Resume" : "Pause")
            .disabled(player.isFinished)
            Button { change { $0.skip(at: .now) } } label: {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel("Skip stretch")
            .disabled(player.isFinished)
        }
        .font(.title)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    private var finishButtons: some View {
        VStack(spacing: 12) {
            Button {
                finish(cooldownCompleted: true)
            } label: {
                Text("Finish workout")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if player?.isFinished != true {
                Button("Skip cool-down") { finish(cooldownCompleted: false) }
            }
            if !WorkoutFlow.hasLoggedSets(session) {
                Text("No sets were logged, so the split stays on this day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Actions

    private func load() {
        guard player == nil else { return }
        let durations = items.map(\.durationSec)
        guard !durations.isEmpty else { return }
        if let saved = CooldownProgress.load(for: session), saved.durations == durations.map({ max($0, 1) }) {
            player = saved
            catchUp()
        } else {
            player = CooldownPlayer(durations: durations, at: .now)
            CooldownProgress.save(player, for: session)
        }
    }

    /// Moves past stretches whose time ran out, with one haptic for the change.
    private func catchUp() {
        guard var updated = player, updated.update(at: .now) > 0 else { return }
        autoAdvances += 1
        player = updated
        CooldownProgress.save(updated, for: session)
    }

    private func change(_ apply: (inout CooldownPlayer) -> Void) {
        guard var updated = player else { return }
        apply(&updated)
        player = updated
        CooldownProgress.save(updated, for: session)
    }

    private func finish(cooldownCompleted: Bool) {
        undo = nil
        CooldownProgress.clear(for: session)
        WorkoutFlow.finish(session, cooldownCompleted: cooldownCompleted, in: context)
        RestTimerService.cancel()
    }
}

/// Where the player is in the sequence, kept per workout so a relaunch resumes the cool-down.
private enum CooldownProgress {
    private static func key(_ session: WorkoutSession) -> String { "cooldown.\(session.id)" }

    static func load(for session: WorkoutSession) -> CooldownPlayer? {
        UserDefaults.standard.data(forKey: key(session)).flatMap { try? JSONDecoder().decode(CooldownPlayer.self, from: $0) }
    }

    static func save(_ player: CooldownPlayer?, for session: WorkoutSession) {
        guard let player, let data = try? JSONEncoder().encode(player) else { return }
        UserDefaults.standard.set(data, forKey: key(session))
    }

    static func clear(for session: WorkoutSession) {
        UserDefaults.standard.removeObject(forKey: key(session))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
