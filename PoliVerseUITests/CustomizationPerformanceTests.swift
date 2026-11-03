import XCTest

/// Same gallery interaction before and after the refactor; no university traffic.
nonisolated final class CustomizationPerformanceTests: XCTestCase {
    @MainActor func testGalleryScrollCost() {
        let app = XCUIApplication()
        app.launchArguments += ["-useMockData", "<true/>", "-hasCompletedOnboarding", "<true/>",
                                "-usesNewInterface", "<true/>", "-appLayout", "tabs", "-ResetTodayStyle",
                                "-lastSeenReleaseVersion", "999", "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        let open = app.buttons["today-customize"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        open.tap()
        XCTAssertTrue(app.buttons["customize-edit"].waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
                          XCTHitchMetric(application: app)], options: options) {
            let first = app.buttons["customize-card-0"].firstMatch
            first.swipeLeft()
            app.buttons["customize-card-1"].firstMatch.swipeRight()
        }
    }
}
