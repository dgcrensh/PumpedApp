import XCTest

final class GymTests: XCTestCase {
    /// Somewhere new → name the gym → it's on the workout header and in Settings → Gyms.
    @MainActor
    func testNamingANewGymAtWorkoutStart() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing-reset-store", "-ui-testing-sample-split",
            "-ui-testing-location", "39.7392,-104.9903",
        ]
        app.launch()

        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let name = app.textFields["new-gym-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "an unknown location asks to name the gym")
        name.tap()
        name.typeText("Downtown")
        app.buttons["Save gym and start"].tap()

        let skip = app.buttons["Skip warmup"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let gym = app.buttons["workout-gym"]
        XCTAssertTrue(gym.waitForExistence(timeout: 5))
        XCTAssertEqual(gym.label, "Downtown")

        app.buttons["Close"].tap()
        app.tabBars.buttons["Settings"].tap()
        let gyms = element(in: app, labelStartingWith: "Gyms")
        XCTAssertTrue(gyms.waitForExistence(timeout: 5))
        gyms.tap()
        XCTAssertTrue(element(in: app, labelStartingWith: "Downtown").waitForExistence(timeout: 5))
    }

    private func element(in app: XCUIApplication, labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }
}
