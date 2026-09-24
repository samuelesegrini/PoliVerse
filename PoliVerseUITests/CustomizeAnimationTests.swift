import XCTest

/// Walks Personalizza from start to finish and keeps a screenshot of every
/// step, so the whole process can be checked by eye after a change.
///
/// Opens the gallery from Oggi, swipes to another look — which is what puts it
/// in use — edits it on a draft, cancels and keeps, deletes a look and brings
/// it back, adds one from a theme with its own app half, and closes by tapping
/// the card.
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
            // Release notes already read, so a fresh install opens on Oggi.
            "-lastSeenReleaseVersion", "999",
            "-AppleLanguages", "(it)",
            "-AppleLocale", "it_IT",
        ]
        return app
    }

    @MainActor func testWholeProcess() throws {
        let app = makeApp()
        app.launch()

        // Swiping is choosing: the look that comes to rest in the middle is
        // the one the app wears, with nothing to confirm.
        _ = open(app)
        XCTAssertTrue(isCentred(card(app, 0), in: app))
        shot(app, "01-gallery")
        card(app, 0).swipeLeft()
        settle()
        shot(app, "02-swiped")
        XCTAssertTrue(isCentred(card(app, 1), in: app), "Swiping did not bring the next look to the middle")
        // Tapping the middle card goes back to the app wearing it.
        card(app, 1).tap()
        settle()
        XCTAssertFalse(card(app, 1).exists, "Tapping the middle card did not close Personalizza")

        let edit = open(app)
        XCTAssertTrue(isCentred(card(app, 1), in: app), "The gallery did not open on the look swiped to")

        // Personalizza grows the card into the editor.
        edit.tap()
        let done = app.buttons["customize-edit-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Personalizza did not open the editor")
        settle()
        shot(app, "03-editor")

        // A zone opens its own controls in a small sheet.
        zone(app, "date").tap()
        settle()
        shot(app, "04-zone")
        reveal(app.buttons["date-font-mono"].firstMatch, in: app).tap()
        settle()
        shot(app, "05-font")
        closePanel(app)
        XCTAssertTrue(done.exists, "Closing a panel stopped editing")

        // A sideways swipe is the next light.
        app.scrollViews.firstMatch.swipeLeft()
        settle()
        shot(app, "06-light")

        // Ripristina, in •••, goes back to where editing started.
        app.buttons["customize-editor-more"].tap()
        let restore = app.buttons["Ripristina"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        XCTAssertTrue(restore.isEnabled, "Editing offered no way back to how the look was")
        restore.tap()
        settle()
        shot(app, "07-restored")

        done.tap()
        settle()
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Fine did not return to the gallery")
        shot(app, "08-gallery")

        // Up lifts the card and shows the trash; the delete can be taken back.
        lift(card(app, 1))
        let trash = app.buttons["customize-trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 3) && trash.isHittable, "Pulling the card up showed no trash")
        shot(app, "08b-lifted")
        trash.tap()
        let undo = app.buttons["customize-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3), "Deleting offered no way back")
        shot(app, "08c-deleted")
        XCTAssertFalse(card(app, todayPresetCount - 1).exists, "The look was not deleted")
        undo.tap()
        settle()
        XCTAssertTrue(card(app, todayPresetCount - 1).exists, "Annulla did not bring the look back")

        // A new look starts from something: here a theme, which opens the
        // editor; Aggiungi asks once about the app.
        app.buttons["customize-add"].tap()
        let preset = app.buttons["customize-new-preset-4"].firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5), "+ did not offer anything to start from")
        shot(app, "09-new")
        preset.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5), "A new look did not open for editing")
        settle()
        shot(app, "10-new-editing")
        done.tap()
        let custom = app.buttons["customize-pair-custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5), "Adding did not ask about the app")
        shot(app, "11-pair-question")
        custom.tap()
        let icon = app.buttons["app-option-icon"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5), "Personalizza l'app did not open the app half")
        icon.tap()
        app.buttons["app-icon-dark"].firstMatch.tap()
        settle()
        shot(app, "12-app-icon")
        app.buttons["app-done"].tap()
        settle()
        XCTAssertTrue(isCentred(card(app, todayPresetCount), in: app), "The new look did not come to the middle")
        XCTAssertTrue(app.staticTexts["App su misura"].exists, "The new look's app is not its own")
        shot(app, "13-added")

        // A side card scrolls to the middle instead of closing.
        card(app, 1).tap()
        settle()
        XCTAssertTrue(isCentred(card(app, 1), in: app), "Tapping a side card did not bring it to the middle")
        XCTAssertTrue(edit.exists, "Tapping a side card left the gallery")

        card(app, 1).tap()
        settle()
        XCTAssertFalse(edit.exists, "Tapping the middle card did not close Personalizza")
        shot(app, "14-closed")
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

    /// Personalises every part of one look through its zones and •••, then uses it.
    @MainActor func testPersonaliseElements() throws {
        let app = makeApp()
        app.launch()

        let edit = open(app)
        edit.tap()
        let done = app.buttons["customize-edit-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        settle()
        shot(app, "30-editor")

        // Flavor from a swatch, from the button bottom-left.
        app.buttons["customize-editor-flavor"].tap()
        settle()
        reveal(app.buttons["flavor-#C2386F"].firstMatch, in: app).tap()
        settle()
        shot(app, "31-flavor")
        closePanel(app)

        // Plotting paper with grain, from •••.
        menu(app, "Carta e motivo")
        app.buttons["paper-plot"].firstMatch.tap()
        reveal(app.sliders["paper-grain"].firstMatch, in: app).adjust(toNormalizedSliderPosition: 0.5)
        settle()
        shot(app, "32-paper")
        closePanel(app)

        // Glowing cards, a tinted light, serif text.
        menu(app, "Superficie delle schede")
        app.buttons["material-glow"].firstMatch.tap()
        closePanel(app)
        app.scrollViews.firstMatch.swipeLeft()
        settle()
        menu(app, "Aspetto e testo")
        reveal(app.buttons["Con grazie"].firstMatch, in: app).tap()
        settle()
        shot(app, "33-appearance")
        closePanel(app)

        // A section's card: swipe to another form, turn it over, change the
        // surface and how much it shows.
        zone(app, "section-upcoming").tap()
        settle()
        shot(app, "34-section-form")
        app.descendants(matching: .any)["form-list"].firstMatch.swipeLeft()
        settle()
        shot(app, "34b-section-form-swiped")
        app.buttons["form-use"].tap()
        settle()
        shot(app, "34c-section-back")
        app.buttons["section-material-glass"].firstMatch.tap()
        app.steppers.firstMatch.buttons.element(boundBy: 1).tap()
        settle()
        shot(app, "34d-section-controls")
        app.buttons["form-done"].tap()
        settle()
        closePanel(app)

        // The bar: no profile button. Settings has no switch: it always stays.
        zone(app, "bar").tap()
        settle()
        XCTAssertFalse(app.switches["Impostazioni"].exists, "Settings can still be hidden from the bar")
        app.switches["Profilo"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        settle()
        closePanel(app)

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
        closePanel(app)

        // Arranging: remove In arrivo, add Esami, drag it above the timetable.
        app.buttons["customize-editor-more"].tap()
        let arrange = app.buttons["Disponi le sezioni"].firstMatch
        XCTAssertTrue(arrange.waitForExistence(timeout: 3))
        arrange.tap()
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
        app.descendants(matching: .any)["date-header-layout"].buttons["Sticker"].firstMatch.tap()
        reveal(app.buttons["sticker-controls-add"].firstMatch, in: app).tap()
        let keyboard = app.textViews["sticker-keyboard"].firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Adding a sticker showed no keyboard field")
        settle()
        keyboard.typeText("🎓")
        settle()
        back(app)
        settle()
        closePanel(app)
        shot(app, "37-sticker")
        app.buttons["zone-stickers-swap"].firstMatch.tap()
        settle()
        shot(app, "38-accessory-text")

        done.tap()
        settle()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        shot(app, "39-gallery")
        card(app, 0).tap()
        settle()
        shot(app, "40-app")
        XCTAssertFalse(app.buttons["bar-profile"].exists, "The bar still shows the profile button")
        XCTAssertTrue(app.buttons["bar-settings"].exists, "The bar lost the settings button")
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

    /// Back from a page pushed inside a panel.
    @MainActor private func back(_ app: XCUIApplication) {
        let back = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3), "The panel page has no back button")
        back.tap()
    }

    @MainActor private func zone(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.buttons["zone-\(id)"].firstMatch
    }

    /// Closes the open panel, back to the page.
    @MainActor private func closePanel(_ app: XCUIApplication) {
        let close = app.buttons["customize-panel-close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 3), "The panel has no close button")
        close.tap()
        settle()
    }

    /// Opens one of the editor's ••• items.
    @MainActor private func menu(_ app: XCUIApplication, _ item: String) {
        app.buttons["customize-editor-more"].tap()
        let button = app.buttons[item].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3), "••• has no \(item)")
        button.tap()
        settle()
    }

    /// Pulls a card up, slowly enough to be a drag rather than a flick.
    @MainActor private func lift(_ card: XCUIElement) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            .press(forDuration: 0.05,
                   thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                   withVelocity: .default, thenHoldForDuration: 0.2)
        settle()
    }

    /// In the single page, the panel steps aside for Personalizza and comes
    /// back when it closes.
    @MainActor func testSinglePage() throws {
        let app = makeApp()
        if let index = app.launchArguments.firstIndex(of: "tabs") { app.launchArguments[index] = "singlePage" }
        app.launch()

        let edit = open(app)
        shot(app, "20-single-gallery")
        card(app, 0).swipeLeft()
        settle()
        XCTAssertTrue(isCentred(card(app, 1), in: app), "Swiping did not choose the next look")
        shot(app, "21-single-swiped")
        card(app, 1).tap()
        settle()
        XCTAssertFalse(edit.exists, "Tapping the middle card did not close Personalizza")

        _ = open(app)
        card(app, 1).tap()
        settle()
        XCTAssertFalse(edit.exists, "Tapping the middle card did not close Personalizza")
        shot(app, "22-single-closed")
    }

    /// The places are reached from the tabs, and the profile from any root.
    @MainActor func testDestinations() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 20))

        app.buttons["bar-profile"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Profilo"].waitForExistence(timeout: 5), "The profile button did not open the profile")
        shot(app, "60-profile")
        app.buttons["BackButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Impostazioni"].waitForExistence(timeout: 3), "The profile did not sit in Impostazioni")
        app.buttons["Chiudi"].firstMatch.tap()
        settle()

        app.buttons["Carriera"].firstMatch.tap()
        let careerProfile = app.buttons["bar-profile"].firstMatch
        XCTAssertTrue(careerProfile.waitForExistence(timeout: 5), "Carriera has no profile button")
        shot(app, "61-career")

        app.buttons["Cerca"].firstMatch.tap()
        let rooms = app.buttons["place-freeRooms"].firstMatch
        XCTAssertTrue(rooms.waitForExistence(timeout: 5), "Cerca does not list the free rooms")
        shot(app, "62-search")
        rooms.tap()
        XCTAssertTrue(app.navigationBars["Aule libere"].waitForExistence(timeout: 5), "Aule libere did not open from Cerca")
        shot(app, "63-free-rooms")
    }

    /// Opens Personalizza from Oggi's bar; returns its Personalizza button.
    @MainActor private func open(_ app: XCUIApplication) -> XCUIElement {
        let customize = app.buttons["today-customize"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 20))
        customize.tap()
        let edit = app.buttons["customize-edit"]
        let opened = edit.waitForExistence(timeout: 5)
        if !opened { shot(app, "99-open-failed") }
        XCTAssertTrue(opened, "Personalizza did not open")
        settle()
        return edit
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
