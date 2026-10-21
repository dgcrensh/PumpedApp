import PumpedCore
import SwiftData
import SwiftUI

/// Workout tab (spec §10): the next split day with Start, or Resume for a workout in progress.
struct WorkoutHomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var inProgress: [WorkoutSession]
    @Query(filter: #Predicate<Split> { $0.isActive }) private var activeSplits: [Split]

    @State private var presented: WorkoutSession?
    @State private var isLocating = false
    /// Asking which gym this is, after location didn't match one.
    @State private var gymPrompt: GymPromptSheet.Reason?
    /// The prompt's answer; the workout starts once the prompt is gone.
    @State private var gymChoice: GymChoice?
    @State private var discarding: WorkoutSession?
    @State private var didAutoResume = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 96.0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Workout")
                .toolbarBackground(NightShift.background, for: .navigationBar)
        }
        .sheet(item: $gymPrompt, onDismiss: startWithChosenGym) { reason in
            GymPromptSheet(reason: reason) { gymChoice = $0 }
        }
        .fullScreenCover(item: $presented, onDismiss: discardIfAsked) { session in
            ActiveWorkoutView(session: session) { discarding = session }
        }
        .onAppear {
            // Reopening the app mid-workout goes straight back to it.
            guard !didAutoResume else { return }
            didAutoResume = true
            presented = inProgress.first
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session = inProgress.first {
            resume(session)
        } else if let split = activeSplits.first, let day = SplitEditing.nextDay(of: split) {
            start(day, of: split)
        } else if let split = activeSplits.first {
            ContentUnavailableView {
                Label("\(split.name) has no days", systemImage: "calendar.badge.plus")
            } description: {
                Text("Add a day, like Push or Legs, and its movements to start training.")
            } actions: {
                NavigationLink("Edit \(split.name)") { SplitDetailView(split: split) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "No split to train",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Create a split with at least one day in the Splits tab, then start your workout here.")
            )
        }
    }

    private func resume(_ session: WorkoutSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dateLine
                hero(label: "In progress", title: session.splitDay?.name ?? "Workout", detail: resumeDetail(session))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(NightShift.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            bigButton("Resume workout") { presented = session }
        }
    }

    private func start(_ day: SplitDay, of split: Split) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dateLine
                hero(label: "Next up", title: day.name, detail: cycleText(split))
                movements(of: day)
                DashboardStats()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(NightShift.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            bigButton(
                isLocating ? "Finding your gym…" : "Start \(day.name)",
                accessibilityLabel: isLocating ? "Finding your gym…" : "Start workout"
            ) {
                Task {
                    await detectGymAndStart()
                    // The rest timer notifies at zero; ask the first time a workout starts.
                    await RestTimerService.requestPermission()
                }
            }
            .disabled(isLocating || day.slots.isEmpty)
        }
    }

    // MARK: Dashboard pieces

    private var dateLine: some View {
        NightShiftLabel(text: Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            .padding(.top, 8)
    }

    /// The day's name, big: what you're about to train.
    private func hero(label: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NightShiftLabel(text: label, color: NightShift.accent)
            Text(title)
                .font(.system(size: heroSize, weight: .black).width(.condensed))
                .textCase(.uppercase)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .foregroundStyle(NightShift.text)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(NightShift.muted)
        }
    }

    private func movements(of day: SplitDay) -> some View {
        let slots = day.orderedSlots
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                HStack(spacing: 14) {
                    Text(String(format: "%02d", index + 1))
                        .font(NightShift.display(.body, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(NightShift.faint)
                        .accessibilityHidden(true)
                    Text(slot.movementType?.name ?? "Unknown movement")
                        .font(.body.weight(.medium))
                        .foregroundStyle(NightShift.text)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                if index < slots.count - 1 {
                    Divider().overlay(NightShift.line)
                }
            }
            if slots.isEmpty {
                Text("\(day.name) has no movements yet, so there's nothing to lift. Add some, or pick a different next day in the Splits tab.")
                    .font(.subheadline)
                    .foregroundStyle(NightShift.muted)
                    .padding(.vertical, 12)
                NavigationLink("Add movements to \(day.name)") { SplitDayEditorView(day: day) }
                    .padding(.bottom, 12)
            }
            if let extras = extrasText(day) {
                Divider().overlay(NightShift.line)
                Text(extras)
                    .font(.footnote)
                    .foregroundStyle(NightShift.muted)
                    .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(NightShift.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func bigButton(_ title: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title.uppercased(), systemImage: "play.fill")
        }
        .buttonStyle(.nightShiftPrimary)
        .accessibilityLabel(accessibilityLabel ?? title)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(NightShift.background)
    }

    // MARK: Starting

    /// Spec §8: a known gym nearby starts straight away; otherwise ask.
    private func detectGymAndStart() async {
        isLocating = true
        let fix = await LocationService.shared.currentFix()
        isLocating = false
        switch GymEditing.detect(fix, in: context) {
        case .matched(let gymID):
            begin(at: GymEditing.gym(gymID, in: context))
        case .newGym(let location):
            gymPrompt = .newGym(location)
        case .pickGym:
            gymPrompt = .noLocation
        case .noGym:
            begin(at: nil)
        }
    }

    private func startWithChosenGym() {
        guard let choice = gymChoice else { return }
        gymChoice = nil
        switch choice {
        case .existing(let gym):
            begin(at: gym)
        case .new(let name, let location):
            begin(at: GymEditing.createGym(named: name, at: location, in: context))
        case .noGym:
            begin(at: nil)
        }
    }

    /// Starts the next day of the active split. The split may have changed while locating.
    private func begin(at gym: Gym?) {
        guard inProgress.isEmpty, let split = activeSplits.first, let day = SplitEditing.nextDay(of: split) else { return }
        var rng = SystemRandomNumberGenerator()
        presented = WorkoutFlow.start(day: day, of: split, gym: gym, in: context, using: &rng)
    }

    private func resumeDetail(_ session: WorkoutSession) -> String {
        let sets = session.entries.reduce(0) { $0 + $1.sets.count }
        let started = "Started \(session.startedAt.formatted(date: .omitted, time: .shortened))"
        return sets == 0 ? started : "\(started) · \(sets) \(sets == 1 ? "set" : "sets") logged"
    }

    /// "Day 2 of 3 · Push Pull Legs".
    private func cycleText(_ split: Split) -> String {
        let cycle = SplitCycle(dayCount: split.days.count, nextDayIndex: split.nextDayIndex)
        let position = cycle.position.map { "Day \($0) of \(split.days.count)" }
        return [position, split.name.isEmpty ? nil : split.name].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Warmup: Rower · Cool-down: Upper Body", or nil when the day sets neither.
    private func extrasText(_ day: SplitDay) -> String? {
        let parts = [
            day.defaultCardio.map { "Warmup: \($0.name)" },
            day.stretchSequence.map { "Cool-down: \($0.name)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func discardIfAsked() {
        guard let session = discarding else { return }
        discarding = nil
        WorkoutFlow.discard(session, in: context)
    }
}

/// Recent training under the day's movements: workouts this week, the last one, and its newest PR.
private struct DashboardStats: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var finished: [WorkoutSession]
    @State private var latestPR: WorkoutSummary.PRHit?

    var body: some View {
        if let last = finished.first {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                tile("This week", value: "\(thisWeek)", detail: thisWeek == 1 ? "workout" : "workouts")
                tile("Last", value: last.splitDay?.name ?? "Workout", detail: lastDetail(last))
                if let latestPR {
                    tile("PR", value: compact(latestPR.record), detail: latestPR.exerciseName, labelColor: NightShift.accent)
                }
            }
            .task(id: last.id) {
                latestPR = HistoryData.prs(in: last, context: context).first
            }
        }
    }

    private var thisWeek: Int {
        finished.filter { Calendar.current.isDate($0.startedAt, equalTo: .now, toGranularity: .weekOfYear) }.count
    }

    private func tile(_ label: String, value: String, detail: String, labelColor: Color = NightShift.muted) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NightShiftLabel(text: label, color: labelColor)
            Text(value)
                .font(NightShift.display(.title2, weight: .bold))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(NightShift.text)
            Text(detail)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(NightShift.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(NightShift.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "Sat · 58 min".
    private func lastDetail(_ session: WorkoutSession) -> String {
        let day = session.startedAt.formatted(.dateTime.weekday(.abbreviated))
        guard let endedAt = session.endedAt else { return day }
        return "\(day) · \(WorkoutSummary.durationText(endedAt.timeIntervalSince(session.startedAt)))"
    }

    /// The record in a few characters: "185 lb", "216 e1RM", "10×135".
    private func compact(_ record: PersonalRecord) -> String {
        switch record {
        case let .heaviestWeight(weight):
            "\(SetValues.format(weight)) lb"
        case let .bestEstimatedOneRepMax(e1RM):
            "\(SetValues.format(e1RM.rounded())) e1RM"
        case let .mostReps(reps, weight):
            SetValues(reps: reps, weightLb: weight).summary
        }
    }
}

#Preview {
    WorkoutHomeView()
        .modelContainer(PreviewData.container)
}
