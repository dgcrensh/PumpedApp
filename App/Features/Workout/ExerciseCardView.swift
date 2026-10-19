import PumpedCore
import SwiftData
import SwiftUI

/// One card's contents (spec §6.2): the exercise's image, the exercise, last session's sets, today's
/// sets, the reps and weight steppers (prefilled from last time) and Log set.
struct ExerciseCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.cardSwipeActions) private var swipeActions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Wide enough for "137.5" at the current text size.
    @ScaledMetric(relativeTo: .title) private var weightFieldWidth = 90.0
    let entry: WorkoutEntry
    let session: WorkoutSession
    let onSwap: () -> Void
    let onHide: () -> Void

    @State private var lastTime: LastTime?
    /// Every earlier set of this exercise, for the PR badge.
    @State private var history: [SetValues] = []
    /// Records the set just logged broke, for the "New PR" flash.
    @State private var newRecords: [PersonalRecord] = []
    @State private var showsProgress = false
    @State private var slotName = ""
    @State private var reps = SetValues.fallback.reps
    @State private var weight = SetValues.fallback.weightLb
    @FocusState private var isEditingWeight: Bool

    private struct LastTime {
        let date: Date
        let sets: [SetValues]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExerciseImageView(exerciseID: entry.exercise?.id)
                // Gives way first when the screen is short, so the logging controls always fit.
                .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 224)
                .layoutPriority(-1)
                .clipped()
                .overlay(alignment: .topLeading) { movementChip }
                .overlay(alignment: .topTrailing) { menu }
            VStack(alignment: .leading, spacing: 14) {
                header
                if let exercise = entry.exercise {
                    history(for: exercise)
                    RestTimerView(session: session)
                    logging
                } else {
                    unavailable
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(NightShift.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(NightShift.line))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        .sensoryFeedback(.success, trigger: entry.sets.count) { old, new in new > old }
        .task(id: entry.exercise?.id) { load() }
        .sheet(isPresented: $showsProgress) {
            if let exercise = entry.exercise {
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                        .historyDestinations()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsProgress = false }
                            }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditingWeight = false }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if entry.isSubstitute {
                Text("Substitute for \(slotName)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(.orange)
                    .background(.orange.opacity(0.15), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let exercise = entry.exercise {
                    Button {
                        showsProgress = true
                    } label: {
                        Text(exercise.name)
                            .font(NightShift.display(.title))
                            .textCase(.uppercase)
                            .foregroundStyle(NightShift.text)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("Shows progress and PRs")
                    .accessibilityIdentifier("card-exercise-name")
                    .cardSwipeAccessibilityActions(swipeActions)
                } else {
                    Text("No available variation")
                        .font(NightShift.display(.title))
                        .textCase(.uppercase)
                        .foregroundStyle(NightShift.text)
                        .accessibilityAddTraits(.isHeader)
                        .cardSwipeAccessibilityActions(swipeActions)
                }
                if entry.exercise?.isLiked == true {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(NightShift.accent)
                        .accessibilityLabel("Liked")
                }
            }
            if let exercise = entry.exercise {
                Text(equipmentText(for: exercise))
                    .font(.subheadline)
                    .foregroundStyle(NightShift.muted)
                    .accessibilityLabel(subtitle(for: exercise))
            }
        }
    }

    /// The slot's movement, on the image. VoiceOver hears it with the equipment instead.
    @ViewBuilder
    private var movementChip: some View {
        let movement = entry.exercise?.movementType?.name ?? slotName
        if !movement.isEmpty {
            Text(movement)
                .font(NightShift.display(.footnote, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(NightShift.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(NightShift.background, in: Capsule())
                .padding(14)
                .accessibilityHidden(true)
        }
    }

    private var menu: some View {
        Menu {
            Button(action: onSwap) {
                Label("Swap variation", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!entry.sets.isEmpty)
            if let exercise = entry.exercise {
                if exercise.isLiked {
                    Button {
                        WorkoutFlow.setLiked(exercise, false, in: context)
                    } label: {
                        Label("Unlike", systemImage: "heart.slash")
                    }
                } else {
                    Button {
                        WorkoutFlow.setLiked(exercise, true, in: context)
                    } label: {
                        Label("Like", systemImage: "heart")
                    }
                }
                Button(role: .destructive, action: onHide) {
                    Label("Never show me this", systemImage: "eye.slash")
                }
                .disabled(!entry.sets.isEmpty)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(NightShift.text)
                .frame(width: 44, height: 44)
                .background(NightShift.background.opacity(0.8), in: Circle())
                .padding(8)
        }
        .accessibilityLabel("Exercise options")
        // After the exercise's name, which carries the swipe actions.
        .accessibilitySortPriority(-1)
    }

    private func history(for exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastTime {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    NightShiftLabel(text: lastTime.date.formatted(.dateTime.month(.abbreviated).day()))
                        .frame(minWidth: 64, alignment: .leading)
                    Text(SetPrefill.summary(lastTime.sets))
                        .font(.subheadline)
                        .foregroundStyle(NightShift.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Last time, \(lastTime.date.formatted(.dateTime.month(.wide).day())): \(SetPrefill.summary(lastTime.sets))")
            } else {
                Text("First time logging this one")
                    .font(.subheadline)
                    .foregroundStyle(NightShift.muted)
            }
            let today = entry.orderedSets
            if !today.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    NightShiftLabel(text: "Today", color: NightShift.accent)
                        .frame(minWidth: 64, alignment: .leading)
                        .accessibilityHidden(true)
                    Text(today.map { WorkoutFlow.values($0).summary }.joined(separator: "  "))
                        .font(NightShift.display(.title3, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(NightShift.text)
                        .accessibilityLabel("Today: \(SetPrefill.summary(today.map(WorkoutFlow.values)))")
                        .accessibilityIdentifier("today-sets")
                    Spacer(minLength: 8)
                    Button {
                        if let last = today.last { WorkoutFlow.deleteSet(last, in: context) }
                        newRecords = []
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundStyle(NightShift.muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove last set")
                }
                prBadge(today.map(WorkoutFlow.values))
            }
        }
    }

    /// Today's PRs on this card (spec §9), recomputed as sets are logged or removed.
    @ViewBuilder
    private func prBadge(_ today: [SetValues]) -> some View {
        let records = PersonalRecords.hits(today: today, history: history)
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label(newRecords.isEmpty ? "PR" : "New PR!", systemImage: "trophy.fill")
                    .font(NightShift.display(.caption, weight: .heavy))
                    .textCase(.uppercase)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(NightShift.onAccent)
                    .background(NightShift.accent, in: Capsule())
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    Text(record.summary)
                        .font(.caption)
                        .foregroundStyle(NightShift.muted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pr-badge")
        }
    }

    private var logging: some View {
        VStack(spacing: 12) {
            // At accessibility text sizes the two steppers stack instead of overflowing the card.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                stepperBox(unit: "Reps") {
                    stepButton("minus", label: "Fewer reps") { reps = max(reps - 1, 1) }
                } value: {
                    Text("\(reps)")
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(reps) reps")
                } more: {
                    stepButton("plus", label: "More reps") { reps = min(reps + 1, 100) }
                }
                stepperBox(unit: "lb") {
                    stepButton("minus", label: "Subtract 5 pounds") { weight = SetPrefill.stepWeight(weight, by: -1) }
                } value: {
                    TextField("Weight", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .focused($isEditingWeight)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: weightFieldWidth)
                        .accessibilityLabel("Weight in pounds")
                } more: {
                    Button {
                        weight = SetPrefill.stepWeight(weight, by: 1)
                    } label: {
                        Text("+5")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(NightShift.accent)
                            .frame(width: 44, height: 44)
                            .background(NightShift.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityLabel("Add 5 pounds")
                }
            }
            Button(action: logSet) {
                Text("Log set \(entry.sets.count + 1)")
            }
            .buttonStyle(.nightShiftPrimary)
            .accessibilityLabel("Log set")
        }
    }

    /// A big number with − and + on either side, on the card's darkest fill.
    private func stepperBox<Less: View, Value: View, More: View>(
        unit: String,
        @ViewBuilder less: () -> Less,
        @ViewBuilder value: () -> Value,
        @ViewBuilder more: () -> More
    ) -> some View {
        HStack(spacing: 4) {
            less()
            VStack(spacing: 0) {
                value()
                    .font(NightShift.display(.title, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(NightShift.text)
                NightShiftLabel(text: unit)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            more()
        }
        .padding(6)
        .background(NightShift.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .foregroundStyle(NightShift.text)
                .frame(width: 44, height: 44)
                .background(NightShift.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing left to pick for \(slotName.isEmpty ? "this slot" : slotName) here. Swap one in by hand, or swipe the card away.")
                .font(.callout)
                .foregroundStyle(NightShift.muted)
            Button("Swap variation", action: onSwap)
                .buttonStyle(.nightShiftSecondary)
        }
    }

    // MARK: Actions

    private func logSet() {
        isEditingWeight = false
        let values = SetValues(reps: reps, weightLb: max(weight, 0))
        newRecords = PersonalRecords.newRecords(
            set: values,
            earlierToday: entry.orderedSets.map(WorkoutFlow.values),
            history: history
        )
        WorkoutFlow.logSet(values, on: entry, in: context)
        RestTimerService.sync(session)
        prefill()
    }

    private func load() {
        if let id = entry.movementTypeID {
            slotName = (try? context.fetch(FetchDescriptor<MovementType>(predicate: #Predicate { $0.id == id })).first?.name) ?? ""
        }
        lastTime = entry.exercise
            .flatMap { WorkoutFlow.lastSets(of: $0.id, before: session, in: context) }
            .map { LastTime(date: $0.date, sets: $0.sets) }
        history = entry.exercise.map { WorkoutFlow.allSets(of: $0.id, before: session, in: context) } ?? []
        newRecords = []
        prefill()
    }

    private func prefill() {
        let values = SetPrefill.values(today: entry.orderedSets.map(WorkoutFlow.values), lastSession: lastTime?.sets ?? [])
        reps = values.reps
        weight = values.weightLb
    }

    private func equipmentText(for exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted()
        return equipment.isEmpty ? "Bodyweight" : equipment.joined(separator: " · ")
    }

    private func subtitle(for exercise: Exercise) -> String {
        let equipment = exercise.equipment.map(\.name).sorted()
        let parts = [exercise.movementType?.name, equipment.isEmpty ? "Bodyweight" : equipment.joined(separator: ", ")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// The exercise's picture: a PNG or JPEG in the app bundle named after the exercise's id (for
/// example `back-squat.png`, added under `App/Resources/ExerciseImages/`), or a placeholder until the
/// image library is added. The slot is landscape, about 3:2, and crops to fill.
struct ExerciseImageView: View {
    let exerciseID: String?

    var body: some View {
        if let exerciseID, let image = UIImage(named: exerciseID) ?? UIImage(named: "\(exerciseID).jpg") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            NightShift.raised
            Canvas { context, size in
                var stripes = Path()
                for x in stride(from: -size.height, to: size.width, by: 20) {
                    stripes.move(to: CGPoint(x: x, y: size.height))
                    stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                }
                context.stroke(stripes, with: .color(.white.opacity(0.035)), lineWidth: 10)
            }
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(NightShift.faint)
        }
        .accessibilityHidden(true)
    }
}
