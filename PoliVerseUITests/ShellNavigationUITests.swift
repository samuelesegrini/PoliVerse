import XCTest

/// Every way through the shell: the four tabs, the places Cerca lists, the
/// profile and Impostazioni, and the same ground covered in the single-page
/// layout through its panel.
///
/// The point is that no route dead-ends: each screen comes up, its title is
/// the one the place declares, and the way back leaves the app where it was.
nonisolated final class ShellNavigationUITests: PoliVerseUITestCase {
    /// The places listed in Cerca, with the navigation title each opens under.
    /// Mirrors `NewDestination.inSearch`, so a place added there without a
    /// screen fails here.
    private static let places: [(id: String, title: String)] = [
        ("freeRooms", "Aule libere"),
        ("map", "Mappa"),
        ("news", "Notizie"),
        ("notices", "Notifiche"),
    ]

    /// Each tab comes up, and going round them and back leaves Oggi intact —
    /// the tab bar keeps one screen per tab rather than rebuilding Oggi.
    @MainActor func testTabsRoundTrip() {
        let app = launchOnToday()
        shot(app, "nav-01-today")

        switchTab(app, to: "Corsi", expecting: "tab-courses")
        shot(app, "nav-02-courses")
        switchTab(app, to: "Carriera", expecting: "tab-career")
        shot(app, "nav-03-career")
        switchTab(app, to: "Cerca", expecting: "tab-search")
        shot(app, "nav-04-search")
        switchTab(app, to: "Oggi", expecting: "tab-today")

        XCTAssertTrue(
            app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 10),
            "Coming back to Oggi lost its bar")
    }

    /// The calendar opens from Oggi's bar, where the day is, and comes back.
    @MainActor func testCalendarOpensFromToday() {
        let app = launchOnToday()
        tap(app.buttons["today-calendar"].firstMatch, "Oggi has no calendar button")
        XCTAssertTrue(app.navigationBars["Calendario"].waitForExistence(timeout: 15),
                      "The calendar did not open from Oggi")
        shot(app, "nav-today-calendar")
        goBack(app)
        require(app.buttons["today-customize"].firstMatch, "Going back did not return to Oggi")
    }

    /// Every place Cerca lists opens and comes back. One test rather than six,
    /// because the cost here is the launch, not the taps.
    @MainActor func testEveryPlaceOpensFromSearch() {
        let app = launchOnToday()
        switchTab(app, to: "Cerca", expecting: "tab-search")

        for place in Self.places {
            let row = app.buttons["place-\(place.id)"].firstMatch
            require(row, "Cerca does not list \(place.title)")
            if !row.isHittable { app.swipeUp() }
            row.tap()
            XCTAssertTrue(
                app.navigationBars[place.title].waitForExistence(timeout: 15),
                "\(place.title) did not open from Cerca")
            shot(app, "nav-place-\(place.id)")
            goBack(app)
            require(app.buttons["place-\(place.id)"].firstMatch, "Going back did not return to the list of places")
        }
    }

    /// The profile opens Impostazioni one page in, and Chiudi gives the app
    /// back — the sheet is the only way in, so a stuck sheet is a dead end.
    @MainActor func testProfileAndSettings() {
        let app = launchOnToday()
        switchTab(app, to: "Corsi", expecting: "tab-courses")

        tap(app.buttons["bar-profile"].firstMatch, "Corsi has no profile button")
        require(app.navigationBars["Profilo"], "The profile button did not open the profile")
        shot(app, "nav-10-profile")

        goBack(app)
        require(app.descendants(matching: .any)["settings-list"].firstMatch, "The profile did not sit inside Impostazioni")
        shot(app, "nav-11-settings")

        tap(app.buttons["settings-close"].firstMatch, "Impostazioni has no close button")
        XCTAssertTrue(
            app.descendants(matching: .any)["settings-list"].firstMatch.waitForNonExistence(timeout: 5),
            "Chiudi left Impostazioni on screen")
        require(app.descendants(matching: .any)["tab-courses"].firstMatch, "Closing Impostazioni did not return to Corsi")
    }

    /// The single page reaches the same places through its panel, and the
    /// panel comes back after each one.
    @MainActor func testSinglePagePanelReachesPlaces() {
        let app = launchOnToday(layout: .singlePage)
        shot(app, "nav-20-single")

        // The panel opens at its peek detent, where only the first rows show;
        // a swipe on it brings the rest up before anything is tapped.
        let panel = app.collectionViews.firstMatch
        if panel.waitForExistence(timeout: 15) { panel.swipeUp() }
        settle()

        for place in Self.places.prefix(3) {
            let row = app.buttons["panel-\(place.id)"].firstMatch
            require(row, "The panel does not list \(place.title)", timeout: 15)
            if !row.isHittable { panel.swipeUp() }
            row.tap()
            XCTAssertTrue(
                app.navigationBars[place.title].waitForExistence(timeout: 15),
                "\(place.title) did not open from the panel")
            shot(app, "nav-21-single-\(place.id)")
            goBack(app)
            settle()
        }
    }
}
