import XCTest

/// Exercises the real connection page with local linking adapters, without asking
/// the university to authenticate a test account.
nonisolated final class ConnectionLinkingUITests: PoliVerseUITestCase {
    @MainActor private func launch(_ state: String, textSize: String? = nil) -> XCUIApplication {
        let app = makeApp(textSize: textSize)
        if let index = app.launchArguments.firstIndex(of: "-hasCompletedOnboarding") {
            app.launchArguments[index + 1] = "<false/>"
        }
        app.launchArguments += ["-PreviewConnections", state]
        if textSize != nil { app.launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        app.launch()
        require(app.otherElements["onboarding-connections"].firstMatch, "Connection page", timeout: 30)
        return app
    }

    @MainActor func testContinueDuringLinking() {
        let app = launch("connecting")
        XCTAssertEqual(app.staticTexts["connection-weBeep-status"].label, "Collegamento in corso…")
        XCTAssertTrue(app.buttons["onboarding-primary"].isEnabled)
        shot(app, "connections-connecting")
        XCTAssertFalse(app.buttons["onboarding-back"].exists)
        tap(app.buttons["onboarding-primary"], "Continue while linking")
        require(app.otherElements["onboarding-studies"].firstMatch, "Studies after connections")
    }

    @MainActor func testRepairIsExplicitAndCanBeCancelled() {
        let app = launch("attention")
        XCTAssertEqual(app.staticTexts["connection-university-status"].label, "Collegato")
        XCTAssertEqual(app.staticTexts["connection-weBeep-status"].label, "Completa l'accesso")
        XCTAssertEqual(app.staticTexts["connection-recordings-status"].label, "Non disponibile al momento")
        shot(app, "connections-attention")
        tap(app.buttons["connection-weBeep-resolve"], "Resolve WeBeep")
        tap(app.buttons["Annulla"].firstMatch, "Cancel repair")
        require(app.buttons["onboarding-primary"], "Continue after cancelling repair")
    }

    @MainActor func testProgressFinishesWithAConnectedResult() {
        let app = launch("progress")
        let result = app.staticTexts["connection-weBeep-status"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Collegato"), object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["connection-weBeep-progress"].exists)
        shot(app, "connections-complete")
    }

    @MainActor func testLargeTextStillAllowsContinuing() {
        let app = launch("offline", textSize: "UICTContentSizeCategoryAccessibilityXL")
        XCTAssertTrue(app.buttons["onboarding-primary"].isHittable)
        let materials = app.staticTexts["connection-weBeep-status"]
        for _ in 0..<4 where !materials.isHittable { app.swipeUp() }
        XCTAssertTrue(materials.isHittable, "Connection results must remain reachable at large text sizes")
        XCTAssertTrue(app.buttons["onboarding-primary"].isHittable)
        shot(app, "connections-large-dark")
        tap(app.buttons["onboarding-primary"], "Continue with large text")
        require(app.otherElements["onboarding-studies"].firstMatch, "Studies after offline connections")
    }
}
