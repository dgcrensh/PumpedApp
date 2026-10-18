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
        XCTAssertTrue(app.staticTexts["Exercises"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Not imported"].exists)
    }
}
