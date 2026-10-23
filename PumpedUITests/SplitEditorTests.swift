import XCTest

final class SplitEditorTests: XCTestCase {
    @MainActor
    func testCreateSplitWithADay() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing-reset-store"]
        app.launch()
        app.tabBars.firstMatch.buttons["Splits"].tap()

        app.navigationBars["Splits"].buttons["New split"].tap()
        fillAlert(in: app, text: "PPL", confirm: "Create")
        let splitRow = element(in: app, labelStartingWith: "PPL")
        XCTAssertTrue(splitRow.waitForExistence(timeout: 5))
        splitRow.tap()

        app.buttons["Add day"].tap()
        fillAlert(in: app, text: "Push", confirm: "Add")
        XCTAssertTrue(app.staticTexts["Next up: Push, day 1 of 1"].waitForExistence(timeout: 5))

        element(in: app, labelStartingWith: "Push").tap()
        app.buttons["Add movement"].tap()
        let press = element(in: app, labelStartingWith: "Horizontal Press")
        XCTAssertTrue(press.waitForExistence(timeout: 5))
        press.tap()
        XCTAssertTrue(app.navigationBars["Add movement"].waitForNonExistence(timeout: 5))
        let slot = element(in: app, labelStartingWith: "Horizontal Press")
        XCTAssertTrue(slot.waitForExistence(timeout: 5))

        // Pin the slot to one exercise.
        slot.tap()
        XCTAssertTrue(app.navigationBars["Pin Horizontal Press"].waitForExistence(timeout: 5))
        element(in: app, labelStartingWith: "Dumbbell Bench Press").tap()
        let pinned = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Pinned to Dumbbell Bench Press"))
            .firstMatch
        XCTAssertTrue(pinned.waitForExistence(timeout: 5))
    }

    @MainActor
    private func fillAlert(in app: XCUIApplication, text: String, confirm: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(text)
        alert.buttons[confirm].tap()
    }

    /// Rows combine their texts into one accessibility label, so match on its start.
    private func element(in app: XCUIApplication, labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }
}
