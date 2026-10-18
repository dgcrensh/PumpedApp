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

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .warmup:
                    WarmupView(session: session)
                case .lifting:
                    LiftingView(session: session, undo: $undo)
                case .cooldown, .complete:
                    CooldownView(session: session, undo: $undo) { dismiss() }
                }
            }
            .navigationTitle(session.splitDay?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
                    Menu {
                        Button("Discard workout", role: .destructive) { isConfirmingDiscard = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Discard this workout?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) {
                    onDiscard()
                    dismiss()
                }
            } message: {
                Text("Its sets are deleted and the split stays on this day.")
            }
        }
    }
}
