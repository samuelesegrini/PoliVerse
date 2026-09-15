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
/// The looks offered before the student makes any; a new one comes after.
private let todayPresetCount = 9

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

        // A zone on the page opens its page in the panel.
        zone(app, "date").tap()
        settle()
        shot(app, "04-zone")
        reveal(app.buttons["date-font-mono"].firstMatch, in: app).tap()
        settle()
        shot(app, "05-font")
        app.buttons["customize-zone-done"].tap()
        settle()
        shot(app, "06-zone-closed")
        XCTAssertTrue(done.exists, "Closing a page closed the editor")

        app.buttons["bento-decoration"].tap()
        settle()
        reveal(app.buttons["Righe"].firstMatch, in: app).tap()
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
        XCTAssertTrue(card(app, todayPresetCount).waitForNonExistence(timeout: 3), "A cancelled new look was kept")

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

    /// Every starter look, one screenshot each, to check them by eye.
    @MainActor func testPresets() throws {
        let app = makeApp()
        app.launch()
        _ = open(app)
        for index in 0..<todayPresetCount {
            XCTAssertTrue(isCentred(card(app, index), in: app), "Look \(index + 1) did not come to the middle")
            shot(app, String(format: "50-preset-%d", index + 1))
            if index < todayPresetCount - 1 {
                card(app, index).swipeLeft()
                settle()
            }
        }
    }

    /// Personalises every part of one look through the panel, then uses it.
    @MainActor func testPersonaliseElements() throws {
        let app = makeApp()
        app.launch()

        let gallery = open(app)
        card(app, 0).tap()
        let done = app.buttons["customize-editor-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        settle()
        shot(app, "30-editor")

        // Flavor from a swatch.
        app.buttons["bento-flavor"].tap()
        settle()
        reveal(app.buttons["flavor-#C2386F"].firstMatch, in: app).tap()
        settle()
        shot(app, "31-flavor")
        app.buttons["customize-zone-done"].tap()
        settle()

        // Plotting paper with grain.
        app.buttons["bento-paper"].tap()
        settle()
        app.buttons["paper-plot"].firstMatch.tap()
        reveal(app.sliders["paper-grain"].firstMatch, in: app).adjust(toNormalizedSliderPosition: 0.5)
        settle()
        shot(app, "32-paper")
        app.buttons["customize-zone-done"].tap()
        settle()

        // Glowing cards, tinted appearance, serif text.
        app.buttons["bento-cards"].tap()
        settle()
        app.buttons["material-glow"].firstMatch.tap()
        app.buttons["customize-zone-done"].tap()
        settle()
        app.buttons["bento-appearance"].tap()
        settle()
        app.buttons["appearance-tinted"].firstMatch.tap()
        reveal(app.buttons["Con grazie"].firstMatch, in: app).tap()
        settle()
        shot(app, "33-appearance")
        app.buttons["customize-zone-done"].tap()
        settle()

        // A section's appearance, from the layout page.
        app.buttons["bento-layout"].tap()
        settle()
        reveal(app.buttons["layout-section-upcoming"].firstMatch, in: app).tap()
        settle()
        app.buttons["section-material"].firstMatch.tap()
        app.buttons["Vetro"].firstMatch.tap()
        app.steppers.firstMatch.buttons.element(boundBy: 1).tap()
        settle()
        shot(app, "34-section")
        app.buttons["customize-zone-done"].tap()
        settle()

        // The bar: no settings button.
        zone(app, "bar").tap()
        settle()
        app.switches["Impostazioni"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        settle()
        app.buttons["customize-zone-done"].tap()
        settle()

        // A greeting of the student's own.
        zone(app, "greeting").tap()
        settle()
        let custom = reveal(app.buttons["greeting-custom"].firstMatch, in: app)
        custom.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Choosing a custom greeting showed no field")
        field.tap()
        field.typeText("Forza e coraggio\n")
        settle()
        app.buttons["customize-zone-done"].tap()
        settle()

        // Arranging: remove In arrivo, add Esami, drag it above the timetable.
        app.buttons["bento-arrange"].tap()
        settle()
        shot(app, "35-arranging")
        app.buttons["section-remove-upcoming"].tap()
        let removed = app.descendants(matching: .any)["section-upcoming"].firstMatch.waitForNonExistence(timeout: 3)
        XCTAssertTrue(removed, "Removing a section left it on the page")
        app.buttons["section-add"].tap()
        app.buttons["Esami"].firstMatch.tap()
        settle()
        let exams = app.descendants(matching: .any)["section-exams"].firstMatch
        let timetable = app.descendants(matching: .any)["section-timetable"].firstMatch
        XCTAssertTrue(exams.waitForExistence(timeout: 3), "Adding a section did not put it on the page")
        exams.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.2,
                   thenDragTo: timetable.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)),
                   withVelocity: .slow, thenHoldForDuration: 0.8)
        settle()
        shot(app, "36-arranged")
        XCTAssertLessThan(exams.frame.minY, timetable.frame.minY, "Dragging a section onto another did not move it")
        app.buttons["customize-arrange-done"].tap()
        settle()

        // An accessory: a sticker from the keyboard, then swap to text.
        zone(app, "stickers").tap()
        settle()
        app.segmentedControls["date-header-layout"].buttons["Sticker"].tap()
        reveal(app.buttons["sticker-controls-add"].firstMatch, in: app).tap()
        let keyboard = app.textViews["sticker-keyboard"].firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Adding a sticker showed no keyboard field")
        settle()
        keyboard.typeText("🎓")
        settle()
        app.buttons["sticker-picker-done"].tap()
        settle()
        app.buttons["customize-zone-done"].tap()
        settle()
        shot(app, "37-sticker")
        app.buttons["zone-stickers-swap"].firstMatch.tap()
        settle()
        shot(app, "38-accessory-text")

        done.tap()
        settle()
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        shot(app, "39-gallery")
        app.buttons["customize-use"].tap()
        settle()
        shot(app, "40-app")
        XCTAssertFalse(app.buttons["Impostazioni"].exists, "The bar still shows the settings button")
    }

    /// Scrolls the open panel page until the element can be tapped.
    @discardableResult
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        var attempts = 0
        while !element.isHittable && attempts < 8 {
            app.collectionViews.firstMatch.swipeUp()
            attempts += 1
        }
        return element
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
        let opened = cancel.waitForExistence(timeout: 5)
        if !opened { shot(app, "99-open-failed") }
        XCTAssertTrue(opened, "Personalizza did not open")
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
