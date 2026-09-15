import XCTest

/// Walks Personalizza from start to finish and keeps a screenshot of every
/// step, so the whole process can be checked by eye after a change.
///
/// Opens the gallery from Oggi, swipes to another look, edits it and saves,
/// uses it, then adds a look and cancels, taps a side card, and closes.
/// Every screenshot is attached to the test report; with
/// `TEST_RUNNER_CUSTOMIZE_SHOTS` set to a folder on the Mac they are also
/// written there.
///
/// Run from the PoliVersePerformance scheme, which holds the UI test target.
nonisolated final class CustomizeAnimationTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-useMockData", "<true/>",
            "-hasCompletedOnboarding", "<true/>",
            "-usesNewInterface", "<true/>",
            "-appLayout", "tabs",
            "-todayStyleLibrary", "",
            "-todayStyleSelection", "0",
            "-todayStyle", "{}",
            "-AppleLanguages", "(it)",
            "-AppleLocale", "it_IT",
        ]
        return app
    }

    @MainActor func testWholeProcess() throws {
        let app = makeApp()
        app.launch()

        let gallery = open(app)
        shot(app, "01-gallery")

        // Swipe to the second look and edit it.
        card(app, 0).swipeLeft()
        settle()
        shot(app, "02-swiped")
        card(app, 1).tap()
        let done = app.buttons["customize-editor-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Tapping the middle card did not open the editor")
        settle()
        shot(app, "03-editor")

        app.buttons["Data"].firstMatch.tap()
        settle()
        shot(app, "04-zone")
        app.buttons.matching(NSPredicate(format: "label == '15'")).element(boundBy: 3).tap()
        settle()
        shot(app, "05-font")
        app.buttons["customize-zone-done"].tap()
        settle()
        shot(app, "06-zone-closed")
        XCTAssertTrue(done.exists, "Closing a zone closed the editor")

        done.tap()
        settle()
        XCTAssertTrue(gallery.waitForExistence(timeout: 5), "Fine did not return to the gallery")
        shot(app, "07-saved")

        app.buttons["customize-use"].tap()
        settle()
        XCTAssertFalse(gallery.exists, "Usa did not close Personalizza")
        shot(app, "08-used")

        // Reopened, it starts on the look just used.
        _ = open(app)
        shot(app, "09-reopened")

        // A new look, cancelled, is not kept.
        app.buttons["customize-add"].tap()
        XCTAssertTrue(app.buttons["customize-editor-cancel"].waitForExistence(timeout: 5), "+ did not open the editor")
        settle()
        shot(app, "10-new")
        app.buttons["customize-editor-cancel"].tap()
        settle()
        shot(app, "11-new-cancelled")
        XCTAssertFalse(card(app, 4).exists, "A cancelled new look was kept")

        // A side card scrolls to the middle instead of opening.
        card(app, 2).tap()
        settle()
        shot(app, "12-side-tapped")
        XCTAssertFalse(app.buttons["customize-editor-done"].exists, "Tapping a side card opened the editor")

        gallery.tap()
        settle()
        XCTAssertFalse(gallery.exists, "Annulla did not close Personalizza")
        shot(app, "13-closed")
    }

    /// Opens Personalizza from Oggi's ••• menu; returns its Annulla button.
    @MainActor private func open(_ app: XCUIApplication) -> XCUIElement {
        let more = app.buttons["Altro"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        let customize = app.buttons["today-customize"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 5))
        customize.tap()
        let cancel = app.buttons["customize-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Personalizza did not open")
        settle()
        return cancel
    }

    @MainActor private func card(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        app.descendants(matching: .any)["customize-card-\(index)"].firstMatch
    }

    private func settle() { Thread.sleep(forTimeInterval: 1.2) }

    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["CUSTOMIZE_SHOTS"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appending(path: "\(name).png"))
        }
    }
}
