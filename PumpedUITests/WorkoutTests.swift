import XCTest

final class WorkoutTests: XCTestCase {
    /// Start → skip warmup → log a set (rest timer starts, then skip it) → swipe the card away →
    /// finish lifting → finish the workout → summary.
    @MainActor
    func testLiftingSessionHappyPath() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing-reset-store", "-ui-testing-sample-split"]
        app.launch()

        XCTAssertTrue(element(in: app, labelStartingWith: "Push").waitForExistence(timeout: 5))
        app.buttons["Start workout"].tap()

        let skip = app.buttons["Skip warmup"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let logSet = app.buttons["Log set"]
        XCTAssertTrue(logSet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 2 done"].exists)
        logSet.tap()
        XCTAssertTrue(app.staticTexts["today-sets"].waitForExistence(timeout: 5))
        let skipRest = app.buttons["Skip rest"]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 5), "logging a set starts the rest timer")
        skipRest.tap()
        XCTAssertTrue(skipRest.waitForNonExistence(timeout: 5))

        app.descendants(matching: .any)["exercise-card"].firstMatch.swipeRight()
        XCTAssertTrue(app.staticTexts["1 of 2 done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["today-sets"].exists, "the next card starts with no sets")

        app.buttons["Finish lifting"].tap()
        let confirm = app.sheets.buttons["Finish lifting"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        let finish = app.buttons["Finish workout"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        XCTAssertTrue(app.navigationBars["Workout complete"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        // Back on the Workout tab, with the split moved on to the next day.
        XCTAssertTrue(element(in: app, labelStartingWith: "Pull").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start workout"].exists)
    }

    /// List rows may combine their texts into one accessibility label, so match on its start.
    private func element(in app: XCUIApplication, labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }
}
