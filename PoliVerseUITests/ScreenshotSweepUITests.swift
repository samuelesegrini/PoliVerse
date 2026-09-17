import XCTest

/// Walks every main screen and keeps a picture of each, in both layouts and at
/// the largest text size.
///
/// Not an assertion suite: it asserts only that each screen came up at all.
/// What it produces is the set of pictures a change is checked against by eye,
/// in one run instead of twenty manual taps — the same job
/// `CustomizeAnimationTests` does for Personalizza, for the rest of the app.
///
/// Run it with `POLIVERSE_UI_SHOTS` pointing at a folder to get the pictures
/// on disk beside each other:
///
///     POLIVERSE_UI_SHOTS=/tmp/poliverse xcodebuild test -scheme PoliVerseUI …
nonisolated final class ScreenshotSweepUITests: PoliVerseUITestCase {
    private static let places: [(id: String, title: String)] = [
        ("calendar", "Calendario"),
        ("freeRooms", "Aule libere"),
        ("map", "Mappa"),
        ("studyPlan", "Piano di studi"),
        ("news", "Notizie"),
        ("notices", "Notifiche"),
    ]

    @MainActor func testSweepAtTheDefaultTextSize() {
        sweep(launchOnToday(), prefix: "sweep-default")
    }

    /// The same walk at AX5, where a screen that assumed a line height gives
    /// way. Pictures rather than assertions: what "broken" looks like here is
    /// a judgement, and the audit suite makes the part that is not.
    @MainActor func testSweepAtTheLargestTextSize() {
        sweep(launchOnToday(textSize: "UICTContentSizeCategoryAccessibilityXXXL"),
              prefix: "sweep-axxxl")
    }

    /// The single page, whose panel shows the same places in a different
    /// shape.
    @MainActor func testSweepOfTheSinglePage() {
        let app = launchOnToday(layout: .singlePage)
        shot(app, "sweep-single-00-today")

        let panel = app.collectionViews.firstMatch
        if panel.waitForExistence(timeout: 15) {
            panel.swipeUp()
            settle()
            shot(app, "sweep-single-01-panel")
        }

        for place in Self.places.prefix(3) {
            let row = app.buttons["panel-\(place.id)"].firstMatch
            guard row.waitForExistence(timeout: 10) else { continue }
            if !row.isHittable { panel.swipeUp() }
            row.tap()
            guard app.navigationBars[place.title].waitForExistence(timeout: 15) else { continue }
            settle()
            shot(app, "sweep-single-\(place.id)")
            goBack(app)
            settle()
        }
    }

    /// Oggi, the three other tabs, each place behind Cerca, and Impostazioni.
    @MainActor private func sweep(_ app: XCUIApplication, prefix: String) {
        shot(app, "\(prefix)-00-today")

        for (title, identifier) in [("Corsi", "tab-courses"), ("Carriera", "tab-career")] {
            switchTab(app, to: title, expecting: identifier)
            settle()
            shot(app, "\(prefix)-01-\(identifier)")
        }

        switchTab(app, to: "Cerca", expecting: "tab-search")
        settle()
        shot(app, "\(prefix)-02-search")

        for place in Self.places {
            let row = app.buttons["place-\(place.id)"].firstMatch
            guard row.waitForExistence(timeout: 10) else {
                XCTFail("Cerca non elenca \(place.title)")
                continue
            }
            if !row.isHittable { app.swipeUp() }
            row.tap()
            XCTAssertTrue(
                app.navigationBars[place.title].waitForExistence(timeout: 20),
                "\(place.title) non si è aperta")
            settle()
            shot(app, "\(prefix)-03-\(place.id)")
            goBack(app)
            settle()
        }

        tap(app.buttons["bar-profile"].firstMatch, "Cerca non ha il pulsante del profilo")
        settle()
        shot(app, "\(prefix)-04-profile")
        goBack(app)
        settle()
        shot(app, "\(prefix)-05-settings")
    }
}
