import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsTabsAndSeededLibrary() throws {
        let app = XCUIApplication()
        app.launch()

        let tabBar = app.tabBars.firstMatch
        for tab in ["Workout", "History", "Splits", "Settings"] {
            XCTAssertTrue(tabBar.buttons[tab].waitForExistence(timeout: 5), "missing \(tab) tab")
        }

        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(element(in: app, labelStartingWith: "Exercises").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Not imported"].exists)
    }

    @MainActor
    func testLibraryBrowserShowsExercisesAndSequences() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.firstMatch.buttons["Settings"].tap()

        element(in: app, labelStartingWith: "Exercises").tap()
        // First row of the first section (Biceps Curl); later sections may not be loaded yet.
        XCTAssertTrue(element(in: app, labelStartingWith: "Barbell Curl").waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        element(in: app, labelStartingWith: "Stretch sequences").tap()
        for name in ["Full Body", "Lower Body", "Upper Body"] {
            XCTAssertTrue(element(in: app, labelStartingWith: name).waitForExistence(timeout: 5), "missing \(name) sequence")
        }
    }

    /// Rows combine their texts into one accessibility label, so match on its start.
    private func element(in app: XCUIApplication, labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }
}
