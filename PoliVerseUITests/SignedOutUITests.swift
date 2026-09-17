import XCTest

/// The app without an account and without sample data — the state a student
/// lands in after signing out, and the one every empty screen is written for.
///
/// It is the easiest state to break and the hardest to notice: development
/// happens on sample data, where nothing is ever empty.
nonisolated final class SignedOutUITests: PoliVerseUITestCase {
    /// Onboarding already done, no account, sample data off: the plain login
    /// screen, not the welcome pages — somebody coming back already knows
    /// what this is.
    @MainActor private func signedOut() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-useMockData", "<false/>",
            "-hasCompletedOnboarding", "<true/>",
            "-usesNewInterface", "<true/>",
            "-AppleLanguages", "(it)",
            "-AppleLocale", "it_IT",
        ]
        return app
    }

    @MainActor func testSignedOutShowsTheLoginScreen() {
        let app = signedOut()
        app.launch()

        require(app.staticTexts["PoliVerse"], "La schermata di accesso non è comparsa", timeout: 30)
        XCTAssertTrue(
            app.buttons.count > 0,
            "La schermata di accesso non offre niente da toccare")
        shot(app, "signedout-01-login")
    }

    /// The disclaimer is not decoration: it is the promise that credentials go
    /// only to the university's own page, and it has to be on the screen that
    /// asks for them.
    @MainActor func testTheLoginScreenSaysItIsNotOfficial() {
        let app = signedOut()
        app.launch()
        require(app.staticTexts["PoliVerse"], "La schermata di accesso non è comparsa", timeout: 30)

        let disclaimer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "non è un'app ufficiale")).firstMatch
        XCTAssertTrue(
            disclaimer.waitForExistence(timeout: 5),
            "La schermata di accesso non dice che l’app non è ufficiale")
    }

    /// The screen that asks for an account is the one that must be reachable
    /// by everyone; it gets the audit too.
    @MainActor func testTheLoginScreenPassesAudit() throws {
        let app = signedOut()
        app.launch()
        require(app.staticTexts["PoliVerse"], "La schermata di accesso non è comparsa", timeout: 30)
        settle()

        try app.performAccessibilityAudit(
            for: [.elementDetection, .hitRegion, .sufficientElementDescription, .trait, .dynamicType]
        ) { issue in
            XCTFail("Accesso: \(issue.compactDescription)")
            return true
        }
    }
}
