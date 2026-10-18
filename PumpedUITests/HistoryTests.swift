import XCTest

final class HistoryTests: XCTestCase {
    /// History → a workout → edit a set → the exercise's progress chart and records.
    @MainActor
    func testWorkoutDetailAndExerciseProgress() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing-reset-store", "-ui-testing-sample-history"]
        app.launch()

        app.tabBars.buttons["History"].tap()
        let newest = app.descendants(matching: .any)["workout-row"].firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        newest.tap()

        let set = app.buttons["set-row"].firstMatch
        XCTAssertTrue(set.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, labelContaining: "Heaviest weight: 190 lb").exists, "the newest workout holds the PRs")
        set.tap()
        XCTAssertTrue(app.navigationBars["Edit set"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        app.buttons["exercise-link"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Barbell Bench Press"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["progress-chart"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, labelContaining: "Heaviest weight").exists)

        app.buttons["All Horizontal Press"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["progress-chart"].firstMatch.waitForExistence(timeout: 5))
    }

    /// The card's exercise name opens its progress.
    @MainActor
    func testCardExerciseNameOpensProgress() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing-reset-store", "-ui-testing-sample-split"]
        app.launch()

        let start = app.buttons["Start workout"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let skip = app.buttons["Skip warmup"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let name = app.buttons["card-exercise-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        XCTAssertTrue(app.buttons["All Horizontal Press"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Log set"].waitForExistence(timeout: 5))
    }

    /// List rows may combine their texts into one accessibility label, so match on part of it.
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }
}
