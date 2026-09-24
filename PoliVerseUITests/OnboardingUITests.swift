import XCTest

/// The first run, which is the one screen every student sees exactly once and
/// nobody ever looks at again while developing.
///
/// Walked on the sample-data route: "Continua con i dati di esempio", on the
/// sign-in step, needs no account and no network, and it is the same journey
/// the account route takes once the sign-in is behind it. The steps offered
/// depend on what the journey knows — signed in, demo, notifications refused —
/// so the walk follows whichever step is on screen rather than a fixed script:
/// the sample data when offered, otherwise the way out, otherwise on.
nonisolated final class OnboardingUITests: PoliVerseUITestCase {
    /// A fresh install: no account, onboarding not done, sample data off until
    /// the student picks it.
    @MainActor private func freshInstall(textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-useMockData", "<false/>",
            "-hasCompletedOnboarding", "<false/>",
            "-usesNewInterface", "<true/>",
            "-AppleLanguages", "(it)",
            "-AppleLocale", "it_IT",
        ]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        return app
    }

    /// The welcome page offers both routes: the questions, and straight to the
    /// account for someone who has used the app before. Neither may be missing —
    /// the second is how a reinstall skips what it already knows.
    @MainActor func testWelcomeOffersBothRoutes() {
        let app = freshInstall()
        app.launch()

        require(app.buttons["onboarding-primary"].firstMatch, "Il benvenuto non offre di iniziare", timeout: 30)
        require(app.buttons["onboarding-signin"].firstMatch, "Il benvenuto non offre l’accesso diretto")
        shot(app, "onboarding-01-welcome")
    }

    /// One move through the journey: the sample data when the step offers it,
    /// otherwise the way out, otherwise the step's own offer. The last step's
    /// offer is what opens the app.
    ///
    /// - Returns: `false` when the step offered nothing to press.
    @MainActor @discardableResult
    private func takeStep(_ app: XCUIApplication, shotName: String? = nil) -> Bool {
        let demo = app.buttons["onboarding-demo"].firstMatch
        let skip = app.buttons["onboarding-skip"].firstMatch
        let primary = app.buttons["onboarding-primary"].firstMatch
        for (button, suffix) in [(demo, "demo"), (skip, "skip"), (primary, "go")] where button.exists && button.isHittable {
            if let shotName { shot(app, "\(shotName)-\(suffix)") }
            button.tap()
            return true
        }
        return false
    }

    /// The whole flow, from the welcome page to the app, taking the offered
    /// step each time and skipping what can be skipped. A setup that cannot be
    /// postponed is a wall, so every step past the sign-in has a way out.
    @MainActor func testSampleDataRouteReachesTheApp() {
        let app = freshInstall()
        app.launch()

        require(app.buttons["onboarding-primary"].firstMatch, "Il benvenuto non è comparso", timeout: 30)

        for step in 0..<10 {
            settle()
            if app.buttons["today-customize"].firstMatch.exists { break }
            guard takeStep(app, shotName: "onboarding-02-step\(step)") else {
                XCTFail("Il passo \(step) dell’onboarding non offre né un avanti né un più tardi")
                return
            }
        }

        require(app.buttons["today-customize"].firstMatch,
                "L’onboarding con i dati di esempio non è arrivato all’app", timeout: 30)
        shot(app, "onboarding-03-app")
    }

    /// Onboarding done once stays done: the second launch opens the app, not
    /// the welcome page.
    @MainActor func testOnboardingIsNotShownTwice() {
        let app = freshInstall()
        app.launch()
        require(app.buttons["onboarding-primary"].firstMatch, "Il benvenuto non è comparso", timeout: 30)

        for _ in 0..<10 {
            settle()
            if app.buttons["today-customize"].firstMatch.exists { break }
            takeStep(app)
        }
        require(app.buttons["today-customize"].firstMatch, "L’onboarding non è arrivato all’app", timeout: 30)

        app.terminate()
        // Without the fresh-install flags: an argument outranks what the app
        // stored, so relaunching with `-hasCompletedOnboarding NO` would test the
        // argument, not the app.
        if let flag = app.launchArguments.firstIndex(of: "-hasCompletedOnboarding") {
            app.launchArguments.removeSubrange(flag...flag + 1)
        }
        if let flag = app.launchArguments.firstIndex(of: "-useMockData") {
            app.launchArguments.removeSubrange(flag...flag + 1)
        }
        app.launch()
        require(app.buttons["today-customize"].firstMatch,
                "Il secondo avvio ha rimostrato l’onboarding", timeout: 30)
        XCTAssertFalse(app.buttons["onboarding-signin"].firstMatch.exists,
                       "Il benvenuto è tornato dopo che l’onboarding era finito")
    }

    /// The first screen at the largest text size, where a fixed-height button
    /// or a two-line title is most likely to give way. Audited rather than
    /// eyeballed.
    @MainActor func testWelcomePassesAuditAtTheLargestTextSize() throws {
        let app = freshInstall(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        app.launch()
        require(app.buttons["onboarding-primary"].firstMatch, "Il benvenuto non è comparso", timeout: 30)
        settle()
        shot(app, "onboarding-04-welcome-axxxl")

        try app.performAccessibilityAudit(
            for: [.elementDetection, .hitRegion, .sufficientElementDescription, .trait, .dynamicType]
        ) { issue in
            XCTFail("Benvenuto ad AX5: \(issue.compactDescription)")
            return true
        }
    }
}
