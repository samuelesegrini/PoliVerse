import XCTest

nonisolated final class LookApplicationUITests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-useMockData", "<true/>", "-hasCompletedOnboarding", "<true/>",
                                "-usesNewInterface", "<true/>", "-appLayout", "tabs", "-ResetTodayStyle",
                                "-lastSeenReleaseVersion", "999", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        return app
    }

    @MainActor private func open(_ app: XCUIApplication) {
        let button = app.buttons["today-customize"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)
        wait(for: [available], timeout: 10)
        button.tap()
        XCTAssertTrue(app.buttons["customize-edit"].waitForExistence(timeout: 10))
    }

    @MainActor func testBrowsingAndClosingKeepTheActiveLook() {
        let app = launch()
        open(app)
        app.buttons["customize-card-0"].swipeLeft()
        let second = app.buttons["customize-card-1"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue((second.value as? String)?.contains("Anteprima") == true)
        app.buttons["customize-close"].tap()
        open(app)
        XCTAssertTrue((app.buttons["customize-card-0"].value as? String)?.contains("In uso") == true)
        app.buttons["customize-card-0"].swipeLeft()
        app.buttons["customize-use"].tap()
        open(app)
        XCTAssertTrue((app.buttons["customize-card-1"].value as? String)?.contains("In uso") == true)
    }

    @MainActor func testSaveAndUseCommitsWithoutPairingQuestion() {
        let app = launch()
        open(app)
        app.buttons["customize-edit"].tap()
        let done = app.buttons["customize-edit-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["customize-pair-custom"].exists)
    }
}
