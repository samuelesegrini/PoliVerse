import XCTest

/// Release information and preview switches stay reachable from Settings.
nonisolated final class ReleaseControlsUITests: PoliVerseUITestCase {
    @MainActor func testHistoryAndBetaRoundTrip() {
        walk(textSize: nil)
    }

    /// Run through scripts/test-release-controls.sh, which sets the simulator appearance.
    @MainActor func testHistoryAndBetaInDarkMode() {
        walk(textSize: nil, appearance: "Dark")
    }

    @MainActor func testHistoryAndBetaAtLargeText() {
        walk(textSize: "UICTContentSizeCategoryAccessibilityXL")
    }

    @MainActor private func walk(textSize: String?, appearance: String = "Light") {
        let app = makeApp(textSize: textSize)
        app.launchArguments += ["-lastSeenReleaseVersion", "2.1"]
        let variant = appearance + (textSize == nil ? "" : "-AX")
        app.launch()
        tap(app.buttons["bar-settings"].firstMatch, "Oggi has no Settings button", timeout: 30)
        let history = app.buttons["settings-release-history"].firstMatch
        reveal(history, in: app)
        history.tap()
        require(app.navigationBars["Tutte le novità"], "Release history did not open")
        shot(app, "releases-history-" + variant)
        goBack(app)
        let beta = app.buttons["settings-beta"].firstMatch
        reveal(beta, in: app)
        beta.tap()
        require(app.navigationBars["Anteprime"], "Beta settings did not open")
        let toggle = app.switches["beta-campus3D"].firstMatch
        require(toggle, "Campus preview has no switch")
        // Start from a known persisted value without pinning the argument domain.
        if toggle.value as? String == "1" { tapSwitch(toggle) }
        tapSwitch(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        shot(app, "releases-beta-enabled-" + variant)
        app.terminate()
        app.launch()
        tap(app.buttons["bar-settings"].firstMatch, "Settings did not survive relaunch", timeout: 30)
        let row = app.buttons["settings-beta"].firstMatch
        reveal(row, in: app)
        row.tap()
        require(app.switches["beta-campus3D"].firstMatch, "Beta switch missing after relaunch")
        XCTAssertEqual(app.switches["beta-campus3D"].firstMatch.value as? String, "1")
        let reset = app.buttons["beta-reset"].firstMatch
        reveal(reset, in: app)
        reset.tap()
        XCTAssertEqual(app.switches["beta-campus3D"].firstMatch.value as? String, "0")
        shot(app, "releases-beta-reset-" + variant)
        goBack(app)
        tap(app.buttons["settings-close"].firstMatch, "Settings could not close")
        require(app.buttons["today-customize"].firstMatch, "Closing settings lost Oggi")
    }

    /// SwiftUI exposes the title and thumb as one accessibility element. Target the thumb.
    @MainActor private func tapSwitch(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Settings row is not reachable")
    }
}
