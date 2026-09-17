import XCTest

/// The first run, which is the one screen every student sees exactly once and
/// nobody ever looks at again while developing.
///
/// Walked on the sample-data route: "Esplora con dati di esempio" needs no
/// account and no network, and it is the same flow the account route takes
/// once the sign-in step is behind it. The steps offered depend on what the
/// flow knows — signed in, demo, WeBeep connected — so the walk follows
/// whichever step is on screen rather than a fixed script.
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

    /// The welcome page offers both routes: an account, and a look around
    /// without one. Neither may be missing — the second is the only way in for
    /// a student who has not signed in yet.
    @MainActor func testWelcomeOffersBothRoutes() {
        let app = freshInstall()
        app.launch()

        require(app.buttons["onboarding-primary"].firstMatch, "Il benvenuto non offre l’accesso", timeout: 30)
        require(app.buttons["onboarding-demo"].firstMatch, "Il benvenuto non offre i dati di esempio")
        shot(app, "onboarding-01-welcome")
    }

    /// The whole flow, from the welcome page to the app, taking the offered
    /// step each time and skipping what can be skipped. A setup that cannot be
    /// postponed is a wall, so every step past the sign-in has a way out.
    @MainActor func testSampleDataRouteReachesTheApp() {
        let app = freshInstall()
        app.launch()

        tap(app.buttons["onboarding-demo"].firstMatch, "Il benvenuto non offre i dati di esempio", timeout: 30)

        // Each step: skip it if it can be skipped, otherwise take its offer.
        // The last step's offer is what opens the app.
        for step in 0..<8 {
            settle()
            if app.buttons["today-customize"].firstMatch.exists { break }

            let skip = app.buttons["onboarding-skip"].firstMatch
            let primary = app.buttons["onboarding-primary"].firstMatch
            if skip.exists && skip.isHittable {
                shot(app, "onboarding-02-step\(step)-skip")
                skip.tap()
            } else if primary.exists && primary.isHittable {
                shot(app, "onboarding-02-step\(step)-go")
                primary.tap()
            } else {
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
        tap(app.buttons["onboarding-demo"].firstMatch, "Il benvenuto non offre i dati di esempio", timeout: 30)

        for _ in 0..<8 {
            settle()
            if app.buttons["today-customize"].firstMatch.exists { break }
            let skip = app.buttons["onboarding-skip"].firstMatch
            let primary = app.buttons["onboarding-primary"].firstMatch
            if skip.exists && skip.isHittable { skip.tap() } else if primary.exists { primary.tap() }
        }
        require(app.buttons["today-customize"].firstMatch, "L’onboarding non è arrivato all’app", timeout: 30)

        app.terminate()
        app.launch()
        require(app.buttons["today-customize"].firstMatch,
                "Il secondo avvio ha rimostrato l’onboarding", timeout: 30)
        XCTAssertFalse(app.buttons["onboarding-demo"].firstMatch.exists,
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
