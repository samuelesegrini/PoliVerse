import XCTest

/// Shared ground for the UI tests: one way to launch the app, one way to wait,
/// one way to keep a screenshot.
///
/// Every test launches on sample data with onboarding already done, so no test
/// depends on an account or on the Politecnico's servers being up. The flags
/// are read from the argument domain of `UserDefaults`, which means the app
/// itself carries no test-only code; booleans are written as plist values
/// because `Session` reads them with `as? Bool` and a bare `YES` is a string
/// there.
///
/// `nonisolated` against the project's main-actor default isolation, which
/// XCTest's own initialisers do not share; the test bodies drive UI and stay
/// on the main actor.
nonisolated class PoliVerseUITestCase: XCTestCase {
    /// The layout the app opens in. Both are exercised: the tab bar and the
    /// single page with its bottom panel.
    enum Layout: String { case tabs, singlePage }

    override func setUp() {
        continueAfterFailure = false
    }

    /// An app configured but not yet launched, so a test can add its own
    /// flags — a text size, a different layout — before starting it.
    @MainActor func makeApp(layout: Layout = .tabs, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-useMockData", "<true/>",
            "-hasCompletedOnboarding", "<true/>",
            "-usesNewInterface", "<true/>",
            "-appLayout", layout.rawValue,
            "-AppleLanguages", "(it)",
            "-AppleLocale", "it_IT",
        ]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        return app
    }

    /// A launched app sitting on Oggi, ready to be driven.
    @discardableResult
    @MainActor func launchOnToday(layout: Layout = .tabs, textSize: String? = nil) -> XCUIApplication {
        let app = makeApp(layout: layout, textSize: textSize)
        app.launch()
        XCTAssertTrue(
            app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 30),
            "The app never reached Oggi")
        return app
    }

    // MARK: Waiting

    /// Waits for an element and fails with a sentence naming what was missing,
    /// rather than the bare `false` an inline assert would print.
    @discardableResult
    @MainActor func require(
        _ element: XCUIElement, _ what: String, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), what, file: file, line: line)
        return element
    }

    /// Taps an element once it is there, so a test never taps into a screen
    /// that is still building itself.
    @MainActor func tap(
        _ element: XCUIElement, _ what: String, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        require(element, what, timeout: timeout, file: file, line: line).tap()
    }

    /// The tab bar button with that label; the labels are Italian because the
    /// app is launched in Italian.
    @MainActor func tabButton(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        // The tab bar's own button: pages have buttons named like the tabs
        // too — the calendar's "Oggi", a place called "Carriera".
        let inBar = app.tabBars.buttons[title].firstMatch
        if inBar.waitForExistence(timeout: 3) { return inBar }
        // Cerca opens on its field, which takes the tab bar's place until
        // the search is closed.
        if app.keyboards.firstMatch.exists {
            for name in ["Chiudi", "Annulla", "Close", "Cancel"] where app.buttons[name].firstMatch.exists {
                app.buttons[name].firstMatch.tap()
                break
            }
            if inBar.waitForExistence(timeout: 3) { return inBar }
        }
        return app.buttons[title].firstMatch
    }

    /// Switches tab and waits for the tab's own screen to come up, which is
    /// what the identifier on each tab's root marks.
    @MainActor func switchTab(
        _ app: XCUIApplication, to title: String, expecting identifier: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        tap(tabButton(app, title), "The tab bar has no \(title) tab", file: file, line: line)
        XCTAssertTrue(
            app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: 10),
            "Tapping \(title) did not bring up its screen", file: file, line: line)
    }

    /// The system back button of the innermost navigation stack.
    @MainActor func goBack(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let back = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "This screen has no back button", file: file, line: line)
        back.tap()
    }

    /// Animations are a second at most anywhere in the app; a settle is cheaper
    /// and steadier than waiting on a particular frame.
    func settle(_ seconds: TimeInterval = 1.0) { Thread.sleep(forTimeInterval: seconds) }

    // MARK: Screenshots

    /// Keeps a screenshot in the test report, and on disk when
    /// `POLIVERSE_UI_SHOTS` names a folder on the Mac.
    @MainActor func shot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["POLIVERSE_UI_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appending(path: "\(name).png"))
        }
    }
}
