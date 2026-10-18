import PumpedCore
import SwiftData
import SwiftUI

/// The lifting phase: the card stack with its swipes, plus Add exercise and Finish lifting (spec §6.2).
struct LiftingView: View {
    @Environment(\.modelContext) private var context
    let session: WorkoutSession
    @Binding var undo: SwipeUndo?

    @State private var swipes = 0
    @State private var notice: String?
    @State private var isSwapping = false
    @State private var isAddingExercise = false
    @State private var isConfirmingHide = false
    @State private var isConfirmingFinish = false
    @State private var isChangingGym = false

    var body: some View {
        let stack = WorkoutFlow.stack(of: session)
        VStack(spacing: 16) {
            progress(stack)
            if let current = stack.current, let entry = session.entries.first(where: { $0.slotOrder == current.id }) {
                SwipeableCard(enabled: enabledSwipes(for: entry), onSwipe: handle) {
                    ExerciseCardView(
                        entry: entry,
                        session: session,
                        onSwap: { isSwapping = true },
                        onHide: { isConfirmingHide = true }
                    )
                }
                .background(alignment: .top) { cardsBehind(stack.pending.count - 1) }
                .id("\(current.id)-\(current.exerciseID ?? "none")")
                .confirmationDialog(
                    "Never show \(entry.exercise?.name ?? "this exercise")?",
                    isPresented: $isConfirmingHide,
                    titleVisibility: .visible
                ) {
                    Button("Never show", role: .destructive, action: hideCurrent)
                } message: {
                    Text("You can bring it back in Settings.")
                }
            } else {
                ContentUnavailableView("No cards left", systemImage: "checkmark.circle")
            }
            Spacer(minLength: 0)
            controls
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) { noticeBanner }
        .sensoryFeedback(.impact(weight: .medium), trigger: swipes)
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            notice = nil
        }
        .sheet(isPresented: $isSwapping) {
            SwapExerciseSheet(session: session) { exerciseID in
                if WorkoutFlow.swapCurrent(to: exerciseID, in: session, context: context) == .hasSets {
                    notice = Self.hasSetsNotice
                }
                undo = nil
            }
        }
        .sheet(isPresented: $isChangingGym) {
            ChangeGymSheet(session: session)
        }
        .sheet(isPresented: $isAddingExercise) {
            AddExerciseSheet { movementTypeID in
                var rng = SystemRandomNumberGenerator()
                WorkoutFlow.addExercise(movementTypeID: movementTypeID, to: session, context: context, using: &rng)
                undo = nil
            }
        }
        .confirmationDialog("Finish lifting?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
            Button("Finish lifting") {
                WorkoutFlow.finishLifting(session, in: context)
                undo = nil
            }
        } message: {
            Text("Cards you haven't done stay unfinished. Next is the cool-down.")
        }
    }

    private static let hasSetsNotice = "You've logged sets on this one. Swipe right when you're done."

    // MARK: Pieces

    private func progress(_ stack: WorkoutStack) -> some View {
        let total = stack.entries.count
        let done = stack.entries.filter { $0.status == .done }.count
        return HStack {
            Text("\(done) of \(total) done")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                isChangingGym = true
            } label: {
                Label(session.gym?.name ?? "No gym", systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("workout-gym")
            .accessibilityHint("Changes the gym")
        }
    }

    /// Edges of up to two waiting cards peeking out under the top one.
    private func cardsBehind(_ count: Int) -> some View {
        ZStack {
            ForEach(Array((1...2).filter { $0 <= count }.reversed()), id: \.self) { depth in
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .padding(.horizontal, CGFloat(depth) * 14)
                    .offset(y: CGFloat(depth) * 12)
            }
        }
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack {
            Button {
                isAddingExercise = true
            } label: {
                Label("Add exercise", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            Spacer()
            Button {
                isConfirmingFinish = true
            } label: {
                Label("Finish lifting", systemImage: "flag.checkered")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice {
            Text(notice)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 72)
                .transition(.opacity)
        }
    }

    // MARK: Actions

    /// A card with sets can't be swapped out, and an empty slot can't be liked or swapped out.
    private func enabledSwipes(for entry: WorkoutEntry) -> Set<SwipeDirection> {
        var directions: Set<SwipeDirection> = [.right, .left]
        if entry.exercise != nil {
            directions.insert(.up)
            if entry.sets.isEmpty { directions.insert(.down) }
        }
        return directions
    }

    private func handle(_ direction: SwipeDirection) {
        var rng = SystemRandomNumberGenerator()
        let outcome = WorkoutFlow.swipe(direction, in: session, context: context, using: &rng)
        switch outcome.result {
        case .applied:
            swipes += 1
            // A down-swipe refills the slot, which an older snapshot would quietly undo.
            undo = outcome.undo
            if direction == .up { notice = "Liked. You'll see it more often." }
        case .hasSets:
            notice = Self.hasSetsNotice
        case .ignored:
            break
        }
    }

    private func hideCurrent() {
        var rng = SystemRandomNumberGenerator()
        if WorkoutFlow.hideCurrent(in: session, context: context, using: &rng) == .hasSets {
            notice = Self.hasSetsNotice
        }
        undo = nil
    }
}

/// "Swap variation": the slot's own movement first, then everything else.
private struct SwapExerciseSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    let onPick: (String) -> Void

    var body: some View {
        let movementTypeID = WorkoutFlow.currentEntry(of: session)?.movementTypeID
        let candidates = WorkoutFlow.swapCandidates(for: session, in: context)
        let same = candidates.filter { $0.movementType?.id == movementTypeID }
        let other = candidates.filter { $0.movementType?.id != movementTypeID }
        NavigationStack {
            List {
                if !same.isEmpty {
                    Section("Same movement") { rows(same) }
                }
                Section("Other exercises") { rows(other) }
            }
            .navigationTitle("Swap variation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func rows(_ exercises: [Exercise]) -> some View {
        ForEach(exercises) { exercise in
            Button {
                onPick(exercise.id)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                    Text(exercise.movementType?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
    }
}

/// "Add exercise": pick a movement type; the app picks the variation.
private struct AddExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MovementType.name) private var movementTypes: [MovementType]
    let onPick: (String) -> Void

    var body: some View {
        NavigationStack {
            List(movementTypes) { movementType in
                Button(movementType.name) {
                    onPick(movementType.id)
                    dismiss()
                }
                .tint(.primary)
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
