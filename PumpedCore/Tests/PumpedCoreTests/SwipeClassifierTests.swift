import XCTest
@testable import PumpedCore

final class SwipeClassifierTests: XCTestCase {
    private let classifier = SwipeClassifier(distanceThreshold: 120, flickThreshold: 280, minimumFlickDistance: 30)

    private func v(_ dx: Double, _ dy: Double) -> SwipeVector { SwipeVector(dx: dx, dy: dy) }

    func testDominantAxisPicksDirection() {
        XCTAssertEqual(classifier.direction(of: v(50, 10)), .right)
        XCTAssertEqual(classifier.direction(of: v(-50, 40)), .left)
        XCTAssertEqual(classifier.direction(of: v(20, 60)), .down)
        XCTAssertEqual(classifier.direction(of: v(-20, -60)), .up)
        XCTAssertNil(classifier.direction(of: .zero))
    }

    func testSlowDragCommitsPastTheDistanceThreshold() {
        XCTAssertNil(classifier.classify(translation: v(100, 0), predictedEnd: v(110, 0)))
        XCTAssertEqual(classifier.classify(translation: v(130, 20), predictedEnd: v(130, 20)), .right)
        XCTAssertEqual(classifier.classify(translation: v(0, -125), predictedEnd: v(0, -125)), .up)
        XCTAssertEqual(classifier.classify(translation: v(-10, 121), predictedEnd: v(-10, 121)), .down)
    }

    func testQuickFlickCommitsBeforeTheDistanceThreshold() {
        XCTAssertEqual(classifier.classify(translation: v(-40, 5), predictedEnd: v(-320, 20)), .left)
        XCTAssertEqual(classifier.classify(translation: v(5, 45), predictedEnd: v(10, 400)), .down)
    }

    func testTinyOrReversedFlicksSpringBack() {
        // Too short to be anything but a tap that wobbled.
        XCTAssertNil(classifier.classify(translation: v(20, 0), predictedEnd: v(500, 0)))
        // Dragged right, then flung back left.
        XCTAssertNil(classifier.classify(translation: v(60, 0), predictedEnd: v(-200, 0)))
        XCTAssertNil(classifier.classify(translation: .zero, predictedEnd: v(500, 0)))
    }

    func testProgressScalesWithDistance() {
        XCTAssertEqual(classifier.progress(of: .zero), 0)
        XCTAssertEqual(classifier.progress(of: v(60, 0)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(classifier.progress(of: v(0, -300)), 1)
    }
}
