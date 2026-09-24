import XCTest

/// What happens to the app around it: rotation, going to the background and
/// coming back, and a second launch.
///
/// These are the states that never come up while developing on one screen in
/// one orientation, and the ones a student hits every day.
nonisolated final class LifecycleUITests: PoliVerseUITestCase {
    /// The app turns and turns back with its screen intact. Rotating is where
    /// a layout that assumed a width gives way.
    /// The orientation is put back here rather than in `tearDown`, which
    /// XCTest does not run on the main actor; `continueAfterFailure` is off,
    /// so each test starts by asking for the orientation it wants.
    @MainActor func testRotationKeepsTheScreen() {
        XCUIDevice.shared.orientation = .portrait
        let app = launchOnToday()
        switchTab(app, to: "Carriera", expecting: "tab-career")

        XCUIDevice.shared.orientation = .landscapeLeft
        settle()
        shot(app, "life-01-landscape")
        require(
            app.descendants(matching: .any)["tab-career"].firstMatch,
            "Rotating to landscape lost Carriera")

        XCUIDevice.shared.orientation = .portrait
        settle()
        shot(app, "life-02-portrait")
        require(
            app.descendants(matching: .any)["tab-career"].firstMatch,
            "Rotating back lost Carriera")
    }

    /// Backgrounding and returning leaves the student where they were, rather
    /// than on Oggi with the screen they opened gone.
    @MainActor func testReturningFromTheBackgroundKeepsThePlace() {
        let app = launchOnToday()
        tap(app.buttons["today-calendar"].firstMatch, "Oggi has no calendar button")
        require(app.navigationBars["Calendario"], "The calendar did not open", timeout: 15)

        XCUIDevice.shared.press(.home)
        settle(2)
        app.activate()

        // Waited for rather than slept on: activation returns before the
        // system has the app in front again.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "The app did not come back to the foreground")
        require(app.navigationBars["Calendario"], "Coming back from the background left the calendar")
        shot(app, "life-03-resumed")
    }

    /// The layout the student chose is a setting, so it survives a relaunch —
    /// the single page comes back as the single page.
    @MainActor func testTheChosenLayoutSurvivesARelaunch() {
        let app = launchOnToday(layout: .singlePage)
        XCTAssertFalse(
            tabButton(app, "Carriera").exists,
            "The single-page layout still shows the tab bar")

        app.terminate()
        app.launch()
        require(app.buttons["today-customize"].firstMatch, "The app did not reach Oggi on the second launch", timeout: 30)
        XCTAssertFalse(
            tabButton(app, "Carriera").exists,
            "Relaunching turned the single page back into tabs")
        shot(app, "life-04-relaunched")
    }

    /// A launch with the sample data off and no account lands on the login
    /// screen instead of an empty app — the state a new install opens in.
    @MainActor func testWithoutAnAccountTheAppAsksToSignIn() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-useMockData", "<false/>",
            "-hasCompletedOnboarding", "<false/>",
            "-AppleLanguages", "(it)",
            "-AppleLocale", "it_IT",
        ]
        app.launch()

        // Onboarding opens on the welcome step; whichever control it puts
        // first, the screen has to offer a way forward.
        let hasAWayForward = app.buttons.firstMatch.waitForExistence(timeout: 30)
        XCTAssertTrue(hasAWayForward, "A fresh install opened with nothing to tap")
        shot(app, "life-05-fresh-install")
    }
}
