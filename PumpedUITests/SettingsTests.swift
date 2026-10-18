import XCTest

final class SettingsTests: XCTestCase {
    /// Settings → Custom exercises → add one → it shows in the list and the library.
    @MainActor
    func testCreateCustomExercise() throws {
        let app = launch()
        element(in: app, labelStartingWith: "Custom exercises").tap()
        XCTAssertTrue(app.staticTexts["No custom exercises"].waitForExistence(timeout: 5))

        app.navigationBars.buttons["New exercise"].tap()
        let name = app.textFields["custom-exercise-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Landmine Press")
        XCTAssertFalse(app.buttons["Save"].isEnabled, "needs a movement")

        element(in: app, labelStartingWith: "Movement").tap()
        let movement = element(in: app, labelStartingWith: "Vertical Press")
        XCTAssertTrue(movement.waitForExistence(timeout: 5))
        movement.tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()

        XCTAssertTrue(element(in: app, labelStartingWith: "Landmine Press").waitForExistence(timeout: 5))
    }

    /// Settings → Custom stretches → add one.
    @MainActor
    func testCreateCustomStretch() throws {
        let app = launch()
        element(in: app, labelStartingWith: "Custom stretches").tap()
        app.navigationBars.buttons["New stretch"].tap()
        let name = app.textFields["custom-stretch-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Wall Calf Stretch")
        app.buttons["Save"].tap()
        XCTAssertTrue(element(in: app, labelStartingWith: "Wall Calf Stretch").waitForExistence(timeout: 5))
    }

    /// The empty states for hidden and liked exercises.
    @MainActor
    func testHiddenAndLikedStartEmpty() throws {
        let app = launch()
        element(in: app, labelStartingWith: "Hidden exercises").tap()
        XCTAssertTrue(app.staticTexts["Nothing hidden"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        element(in: app, labelStartingWith: "Liked exercises").tap()
        XCTAssertTrue(app.staticTexts["No liked exercises"].waitForExistence(timeout: 5))
    }

    /// Debug → generate fake history → History lists it.
    @MainActor
    func testDebugMenuGeneratesHistory() throws {
        let app = launch()
        let debug = app.buttons["Debug"]
        app.swipeUp()
        XCTAssertTrue(debug.waitForExistence(timeout: 5))
        debug.tap()
        app.buttons["Generate 6 months of history"].tap()
        XCTAssertTrue(element(in: app, labelStartingWith: "Added").waitForExistence(timeout: 10))

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["workout-row"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing-reset-store"]
        app.launch()
        app.tabBars.firstMatch.buttons["Settings"].tap()
        return app
    }

    /// Rows combine their texts into one accessibility label, so match on its start.
    private func element(in app: XCUIApplication, labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }
}
