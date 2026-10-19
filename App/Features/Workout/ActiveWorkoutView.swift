import SwiftUI

/// A workout in progress, shown full screen: warmup, lifting, then cool-down (spec §6).
///
/// Everything is saved as it happens, so closing this (or the app being killed) leaves the workout
/// to resume from the Workout tab.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    /// Asks the presenter to delete the workout once this view is gone.
    let onDiscard: () -> Void

    @State private var undo: SwipeUndo?
    @State private var isConfirmingDiscard = false
    @State private var isChangingGym = false

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .warmup:
                    WarmupView(session: session)
                case .lifting:
                    LiftingView(session: session, undo: $undo)
                case .cooldown:
                    CooldownView(session: session, undo: $undo)
                case .complete:
                    WorkoutSummaryView(session: session) { dismiss() }
                }
            }
            .navigationTitle(session.splitDay?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NightShift.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Swipes, undo and Finish lifting all change the phase; the rest notification only
            // belongs to lifting.
            .onChange(of: session.phase) { RestTimerService.sync(session) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // The summary has its own Done button.
                    if session.phase != .complete {
                        Button("Close") { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let undo {
                        Button {
                            WorkoutFlow.undo(undo, in: session, context: context)
                            self.undo = nil
                        } label: {
                            Label("Undo \(undo.direction.actionName.lowercased())", systemImage: "arrow.uturn.backward")
                        }
                    }
                    if session.phase != .complete {
                        Menu {
                            Button {
                                isChangingGym = true
                            } label: {
                                Label("Change gym", systemImage: "mappin.and.ellipse")
                            }
                            Button("Discard workout", role: .destructive) { isConfirmingDiscard = true }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $isChangingGym) {
                ChangeGymSheet(session: session)
            }
            .confirmationDialog("Discard this workout?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) {
                    RestTimerService.cancel()
                    onDiscard()
                    dismiss()
                }
            } message: {
                Text("Its sets are deleted and the split stays on this day.")
            }
        }
        .nightShiftTheme()
    }
}
