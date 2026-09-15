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
            "-ResetTodayStyle",
            "-AppleLanguages", "(it)",
            "-AppleLocale", "it_IT",
        ]
        return app
    }

    @MainActor func testWholeProcess() throws {
        let app = makeApp()
        app.launch()

        // Choose the second look, so the one in use is not the first card.
        let gallery = open(app)
        XCTAssertTrue(isCentred(card(app, 0), in: app))
        card(app, 0).swipeLeft()
        settle()
        app.buttons["customize-use"].tap()
        settle()
        XCTAssertFalse(gallery.exists, "Usa did not close Personalizza")

        _ = open(app)
        shot(app, "01-gallery")
        XCTAssertTrue(isCentred(card(app, 1), in: app), "The gallery did not open on the look in use")

        // Swipe to the third look and edit it.
        card(app, 1).swipeLeft()
        settle()
        shot(app, "02-swiped")
        XCTAssertTrue(isCentred(card(app, 2), in: app), "Swiping did not bring the next look to the middle")
        card(app, 2).tap()
        let done = app.buttons["customize-editor-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Tapping the middle card did not open the editor")
        settle()
        shot(app, "03-editor")

        app.buttons["Data"].firstMatch.tap()
        settle()
        shot(app, "04-zone")
        let mono = app.buttons["date-font-mono"].firstMatch
        if !mono.isHittable { app.collectionViews.firstMatch.swipeUp() }
        mono.tap()
        settle()
        shot(app, "05-font")
        app.buttons["customize-zone-done"].tap()
        settle()
        shot(app, "06-zone-closed")
        XCTAssertTrue(done.exists, "Closing a zone closed the editor")

        app.buttons["customize-editor-background"].tap()
        settle()
        app.buttons["Righe"].firstMatch.tap()
        settle()
        shot(app, "06b-background")
        app.buttons["customize-zone-done"].tap()
        settle()

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
        XCTAssertTrue(card(app, 4).waitForNonExistence(timeout: 3), "A cancelled new look was kept")

        // A side card scrolls to the middle instead of opening.
        XCTAssertTrue(isCentred(card(app, 2), in: app), "Reopened, the gallery was not on the look just used")
        card(app, 3).tap()
        settle()
        shot(app, "12-side-tapped")
        XCTAssertTrue(isCentred(card(app, 3), in: app), "Tapping a side card did not bring it to the middle")
        XCTAssertFalse(app.buttons["customize-editor-done"].exists, "Tapping a side card opened the editor")

        gallery.tap()
        settle()
        XCTAssertFalse(gallery.exists, "Annulla did not close Personalizza")
        shot(app, "13-closed")
    }

    /// Personalises every kind of element on one look, then uses it: a
    /// section's card, the bar and its colour, a custom greeting, arranging
    /// the sections, and a sticker beside the date.
    @MainActor func testPersonaliseElements() throws {
        let app = makeApp()
        app.launch()

        let gallery = open(app)
        card(app, 0).tap()
        let done = app.buttons["customize-editor-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        settle()
        shot(app, "30-editor")

        // A section's appearance.
        zone(app, "section-upcoming").tap()
        settle()
        app.buttons["Vetro"].firstMatch.tap()
        app.steppers.firstMatch.buttons.element(boundBy: 1).tap()
        settle()
        shot(app, "31-section")
        app.buttons["customize-zone-done"].tap()
        settle()

        // The bar: no settings button, rose controls.
        zone(app, "bar").tap()
        settle()
        // The switch itself: a tap in the middle of the row lands on its label.
        app.switches["Impostazioni"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["accent-rose"].firstMatch.tap()
        settle()
        shot(app, "32-bar")
        app.buttons["customize-zone-done"].tap()
        settle()

        // A greeting of the student's own.
        zone(app, "greeting").tap()
        settle()
        let custom = app.buttons["greeting-custom"].firstMatch
        if !custom.isHittable { app.collectionViews.firstMatch.swipeUp() }
        custom.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Choosing a custom greeting showed no field")
        field.tap()
        field.typeText("Forza e coraggio\n")
        settle()
        shot(app, "33-greeting")
        app.buttons["customize-zone-done"].tap()
        settle()

        // Arranging: remove In arrivo, add Esami, drag it above the timetable.
        app.buttons["customize-editor-arrange"].tap()
        settle()
        shot(app, "34-arranging")
        app.buttons["section-remove-upcoming"].tap()
        settle()
        XCTAssertFalse(app.descendants(matching: .any)["section-upcoming"].exists, "Removing a section left it on the page")
        app.buttons["section-add"].tap()
        app.buttons["Esami"].firstMatch.tap()
        settle()
        let exams = app.descendants(matching: .any)["section-exams"].firstMatch
        let timetable = app.descendants(matching: .any)["section-timetable"].firstMatch
        XCTAssertTrue(exams.waitForExistence(timeout: 3), "Adding a section did not put it on the page")
        exams.press(forDuration: 1.2, thenDragTo: timetable, withVelocity: .slow, thenHoldForDuration: 0.8)
        settle()
        shot(app, "35-arranged")
        XCTAssertLessThan(exams.frame.minY, timetable.frame.minY, "Dragging a section onto another did not move it")
        app.buttons["customize-arrange-done"].tap()
        settle()

        // A sticker beside the date.
        zone(app, "date").tap()
        settle()
        app.segmentedControls["date-header-layout"].buttons["Data e sticker"].tap()
        app.buttons["customize-zone-done"].tap()
        settle()
        zone(app, "stickers").tap()
        settle()
        shot(app, "36a-sticker-controls")
        app.buttons["sticker-controls-add"].tap()
        let keyboard = app.textViews["sticker-keyboard"].firstMatch
        let shown = keyboard.waitForExistence(timeout: 5)
        shot(app, "36b-sticker-picker")
        XCTAssertTrue(shown, "Adding a sticker showed no keyboard field")
        settle()
        keyboard.typeText("🎓")
        settle()
        shot(app, "36-sticker-picked")
        app.buttons["sticker-picker-done"].tap()
        settle()
        shot(app, "37-sticker-controls")
        app.buttons["customize-zone-done"].tap()
        settle()
        shot(app, "38-editor-done")

        done.tap()
        settle()
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        shot(app, "39-gallery")
        app.buttons["customize-use"].tap()
        settle()
        shot(app, "40-app")
        XCTAssertFalse(app.buttons["Impostazioni"].exists, "The bar still shows the settings button")
    }

    @MainActor private func zone(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.buttons["zone-\(id)"].firstMatch
    }

    /// In the single page, the panel steps aside for Personalizza and comes
    /// back when it closes.
    @MainActor func testSinglePage() throws {
        let app = makeApp()
        if let index = app.launchArguments.firstIndex(of: "tabs") { app.launchArguments[index] = "singlePage" }
        app.launch()

        let cancel = open(app)
        shot(app, "20-single-gallery")
        app.buttons["customize-use"].tap()
        settle()
        XCTAssertFalse(cancel.exists, "Usa did not close Personalizza")
        shot(app, "21-single-closed")

        _ = open(app)
        cancel.tap()
        settle()
        XCTAssertFalse(cancel.exists, "Annulla did not close Personalizza")
        shot(app, "22-single-cancelled")
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

    @MainActor private func isCentred(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && abs(element.frame.midX - app.frame.midX) < 20
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
