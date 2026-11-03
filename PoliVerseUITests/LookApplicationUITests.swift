import UIKit
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
        XCTAssertEqual(done.label, "Salva e usa")
        XCTAssertEqual(app.buttons["customize-editor-cancel"].label, "Annulla personalizzazione")
        for id in ["customize-editor-cancel", "customize-editor-undo", "customize-editor-redo",
                   "customize-editor-more", "customize-edit-done"] {
            let button = app.buttons[id]
            XCTAssertGreaterThanOrEqual(button.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44, id)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Editor toolbar"
        shot.lifetime = .keepAlways
        add(shot)
        done.tap()
        XCTAssertTrue(app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["customize-pair-custom"].exists)
    }

    @MainActor func testUnappliedLookKeepsTitleClearOfToolbarActions() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "The centered title belongs to the iPad editor")
        let app = launch()
        open(app)
        app.buttons["customize-card-0"].swipeLeft()
        XCTAssertTrue(app.buttons["customize-card-1"].waitForExistence(timeout: 5))
        app.buttons["customize-edit"].tap()
        XCTAssertTrue(app.buttons["customize-edit-done"].waitForExistence(timeout: 10))
        let title = app.staticTexts["customize-look-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let name = app.textFields["customize-name-field"]
        name.tap()
        let previous = name.value as? String ?? ""
        let longName = "Il mio look per studiare"
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + longName)
        XCTAssertEqual(title.label, longName)
        let save = app.buttons["customize-save-library"]
        XCTAssertTrue(save.exists)
        for id in ["customize-editor-cancel", "customize-editor-undo", "customize-editor-redo",
                   "customize-save-library", "customize-editor-more", "customize-edit-done"] {
            XCTAssertFalse(title.frame.intersects(app.buttons[id].frame), id)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Unapplied look toolbar"
        shot.lifetime = .keepAlways
        add(shot)
    }

}
