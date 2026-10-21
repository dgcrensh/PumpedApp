import PumpedCore
import SwiftUI

extension SwipeDirection {
    /// The action's name, for Undo.
    var actionName: String {
        switch self {
        case .right: "Done"
        case .left: "Later"
        case .up: "Like"
        case .down: "Unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .right: "checkmark.circle.fill"
        case .left: "arrow.uturn.backward.circle.fill"
        case .up: "heart.circle.fill"
        case .down: "nosign"
        }
    }

    var tint: Color {
        switch self {
        case .right: .green
        case .left: .orange
        case .up: .pink
        case .down: .red
        }
    }
}

extension SwipeDirection {
    /// The VoiceOver action that stands in for the swipe.
    var accessibilityActionName: String {
        switch self {
        case .right: "Done"
        case .left: "Later"
        case .up: "Like"
        case .down: "Equipment unavailable"
        }
    }
}

/// The top card's swipes, handed to the card's contents so its first element can offer them as
/// VoiceOver actions. Actions on the card's container aren't reachable, because the container
/// itself never gets VoiceOver focus.
struct CardSwipeActions {
    let enabled: Set<SwipeDirection>
    let perform: (SwipeDirection) -> Void
}

private struct CardSwipeActionsKey: EnvironmentKey {
    static let defaultValue: CardSwipeActions? = nil
}

extension EnvironmentValues {
    var cardSwipeActions: CardSwipeActions? {
        get { self[CardSwipeActionsKey.self] }
        set { self[CardSwipeActionsKey.self] = newValue }
    }
}

extension View {
    /// Adds the card's enabled swipes as named VoiceOver actions: Done, Later, Like, Equipment
    /// unavailable.
    func cardSwipeAccessibilityActions(_ actions: CardSwipeActions?) -> some View {
        accessibilityActions {
            if let actions {
                ForEach(SwipeDirection.allCases.filter { actions.enabled.contains($0) }, id: \.self) { direction in
                    Button(direction.accessibilityActionName) { actions.perform(direction) }
                }
            }
        }
    }
}

/// The draggable top card. Recognizes the four swipes with `SwipeClassifier` and animates the card
/// away before reporting the swipe. The card's movement and tilt are the only feedback while
/// dragging: no direction labels are shown on it.
///
/// Directions not in `enabled` spring back. A like (up) bounces back, since that card stays.
/// With `allowsDrag` off (large accessibility text, where the card scrolls instead) the swipes are
/// only reachable through VoiceOver actions and the buttons the lifting screen shows.
struct SwipeableCard<Content: View>: View {
    var enabled: Set<SwipeDirection> = Set(SwipeDirection.allCases)
    var allowsDrag = true
    var classifier: SwipeClassifier = .default
    let onSwipe: (SwipeDirection) -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGSize = .zero
    @State private var isCommitting = false

    var body: some View {
        content()
            .environment(\.cardSwipeActions, CardSwipeActions(enabled: enabled, perform: report))
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width) / 25), anchor: .bottom)
            .gesture(drag, including: allowsDrag ? .all : .subviews)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("exercise-card")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isCommitting else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isCommitting else { return }
                let direction = classifier.classify(
                    translation: vector(value.translation),
                    predictedEnd: vector(value.predictedEndTranslation)
                )
                guard let direction, enabled.contains(direction) else {
                    withAnimation(.spring(duration: 0.3)) { offset = .zero }
                    return
                }
                commit(direction)
            }
    }

    private func commit(_ direction: SwipeDirection) {
        isCommitting = true
        if direction == .up {
            // The liked card stays on top: report right away and spring back.
            onSwipe(.up)
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { offset = .zero } completion: {
                isCommitting = false
            }
            return
        }
        withAnimation(.easeIn(duration: 0.18)) { offset = offscreen(direction) } completion: {
            onSwipe(direction)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { offset = .zero }
            isCommitting = false
        }
    }

    private func report(_ direction: SwipeDirection) {
        guard enabled.contains(direction) else { return }
        onSwipe(direction)
    }

    private func offscreen(_ direction: SwipeDirection) -> CGSize {
        switch direction {
        case .right: CGSize(width: 700, height: offset.height)
        case .left: CGSize(width: -700, height: offset.height)
        case .down: CGSize(width: offset.width, height: 900)
        case .up: CGSize(width: offset.width, height: -900)
        }
    }

    private func vector(_ size: CGSize) -> SwipeVector {
        SwipeVector(dx: Double(size.width), dy: Double(size.height))
    }
}
