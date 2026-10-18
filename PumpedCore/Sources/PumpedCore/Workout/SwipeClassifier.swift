/// The four card swipes (spec §6.2).
public enum SwipeDirection: String, Codable, CaseIterable, Sendable {
    /// Done with this exercise for today.
    case right
    /// Come back to this later.
    case left
    /// Like; the card stays.
    case up
    /// Equipment unavailable; the slot is refilled.
    case down
}

/// A drag translation in screen points. Y grows downward, as on screen.
public struct SwipeVector: Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = SwipeVector(dx: 0, dy: 0)

    /// How far the vector reaches in `direction` (negative when it points the other way).
    public func component(along direction: SwipeDirection) -> Double {
        switch direction {
        case .right: dx
        case .left: -dx
        case .down: dy
        case .up: -dy
        }
    }
}

/// Turns a drag on the top card into a swipe: the drag's dominant axis picks the direction, and it
/// commits when the card has travelled far enough, or when a quick flick would carry it that far.
public struct SwipeClassifier: Equatable, Sendable {
    /// Distance in points that commits a swipe however slowly it was dragged.
    public var distanceThreshold: Double
    /// Distance the drag's predicted end (where its velocity would carry it) must reach for a flick.
    public var flickThreshold: Double
    /// A flick still has to move the card at least this far, so a twitch on a button doesn't swipe.
    public var minimumFlickDistance: Double

    public init(distanceThreshold: Double = 120, flickThreshold: Double = 280, minimumFlickDistance: Double = 30) {
        self.distanceThreshold = distanceThreshold
        self.flickThreshold = flickThreshold
        self.minimumFlickDistance = minimumFlickDistance
    }

    public static let `default` = SwipeClassifier()

    /// The direction a drag is heading, for the on-card label while dragging. Nil when it hasn't moved.
    public func direction(of translation: SwipeVector) -> SwipeDirection? {
        guard translation != .zero else { return nil }
        if abs(translation.dx) >= abs(translation.dy) {
            return translation.dx > 0 ? .right : .left
        }
        return translation.dy > 0 ? .down : .up
    }

    /// 0...1: how close the drag is to committing by distance. Drives the label's opacity.
    public func progress(of translation: SwipeVector) -> Double {
        guard let direction = direction(of: translation) else { return 0 }
        return min(max(translation.component(along: direction) / distanceThreshold, 0), 1)
    }

    /// The swipe a finished drag commits to, or nil when the card should spring back.
    public func classify(translation: SwipeVector, predictedEnd: SwipeVector) -> SwipeDirection? {
        guard let direction = direction(of: translation) else { return nil }
        let distance = translation.component(along: direction)
        if distance >= distanceThreshold { return direction }
        if distance >= minimumFlickDistance && predictedEnd.component(along: direction) >= flickThreshold {
            return direction
        }
        return nil
    }
}
