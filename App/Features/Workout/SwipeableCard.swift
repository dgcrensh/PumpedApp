import PumpedCore
import SwiftUI

extension SwipeDirection {
    /// The action's name on the card while dragging, and for VoiceOver.
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

/// The draggable top card. Recognizes the four swipes with `SwipeClassifier`, labels the action
/// while dragging, and animates the card away before reporting the swipe.
///
/// Directions not in `enabled` spring back. A like (up) bounces back, since that card stays.
struct SwipeableCard<Content: View>: View {
    var enabled: Set<SwipeDirection> = Set(SwipeDirection.allCases)
    var classifier: SwipeClassifier = .default
    let onSwipe: (SwipeDirection) -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGSize = .zero
    @State private var isCommitting = false

    var body: some View {
        content()
            .overlay(alignment: .top) { dragLabel }
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width) / 25), anchor: .bottom)
            .gesture(drag)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("exercise-card")
            .accessibilityAction(named: "Done") { report(.right) }
            .accessibilityAction(named: "Later") { report(.left) }
            .accessibilityAction(named: "Like") { report(.up) }
            .accessibilityAction(named: "Equipment unavailable") { report(.down) }
    }

    @ViewBuilder
    private var dragLabel: some View {
        let translation = vector(offset)
        if let direction = classifier.direction(of: translation), !isCommitting || direction == .up {
            let isEnabled = enabled.contains(direction)
            Label(isEnabled ? direction.actionName : "Not now", systemImage: isEnabled ? direction.systemImage : "xmark.circle")
                .font(.title2.weight(.heavy))
                .textCase(.uppercase)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isEnabled ? direction.tint : .secondary)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(isEnabled ? direction.tint : .secondary, lineWidth: 3))
                .opacity(classifier.progress(of: translation))
                .padding(.top, 24)
                .allowsHitTesting(false)
        }
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
