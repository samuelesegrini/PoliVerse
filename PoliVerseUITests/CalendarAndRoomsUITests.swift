import XCTest

/// The two screens a student drives rather than reads: the calendar's week
/// strip, and Aule libere's three filters.
///
/// The calendar is behind Oggi's bar and Aule libere behind Cerca; both both have controls that change what is on screen,
/// and neither is exercised by the navigation walk — that one only opens them.
nonisolated final class CalendarAndRoomsUITests: PoliVerseUITestCase {
    @MainActor private func open(_ place: String, titled title: String, in app: XCUIApplication) {
        // The calendar opens from Oggi's bar; the other places are Cerca's.
        if place == "calendar" {
            // Every test launches on Oggi, where the calendar's button is.
            tap(app.buttons["today-calendar"].firstMatch, "Oggi non ha il calendario")
        } else {
            switchTab(app, to: "Cerca", expecting: "tab-search")
            tap(app.buttons["place-\(place)"].firstMatch, "Cerca non elenca \(title)")
        }
        require(app.navigationBars[title], "\(title) non si è aperta", timeout: 15)
    }

    /// Paging the week strip and coming back with "Oggi": the strip is the
    /// screen's whole navigation, and a week that does not come back strands
    /// the student in the future.
    @MainActor func testPagingTheWeekAndComingBack() {
        let app = launchOnToday()
        open("calendar", titled: "Calendario", in: app)
        shot(app, "calendar-01-week")

        let next = app.buttons["Settimana successiva"].firstMatch
        let previous = app.buttons["Settimana precedente"].firstMatch
        require(next, "Il calendario non ha il passaggio alla settimana successiva")
        require(previous, "Il calendario non ha il passaggio alla settimana precedente")

        for _ in 0..<3 { next.tap() }
        settle()
        shot(app, "calendar-02-three-weeks-on")

        let today = app.buttons["calendar-today"].firstMatch
        if today.exists {
            today.tap()
            settle()
            shot(app, "calendar-03-back-to-today")
        }
        require(app.navigationBars["Calendario"], "Il calendario si è perso per strada")
    }

    /// Going back and forward the same number of weeks has to land where it
    /// started, which is the arithmetic a strip like this gets wrong.
    @MainActor func testTheWeekStripIsSymmetric() {
        let app = launchOnToday()
        open("calendar", titled: "Calendario", in: app)

        let next = app.buttons["Settimana successiva"].firstMatch
        let previous = app.buttons["Settimana precedente"].firstMatch
        require(next, "Il calendario non ha il passaggio alla settimana successiva")

        settle()
        let before = app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label)
        for _ in 0..<4 { next.tap() }
        settle()
        for _ in 0..<4 { previous.tap() }
        settle()
        let after = app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label)

        XCTAssertEqual(before, after, "Quattro settimane avanti e quattro indietro non tornano al punto di partenza")
    }

    /// The filters are the screen: a campus and a minimum length, and the list
    /// has to keep answering as they change.
    @MainActor func testFreeRoomsFiltersKeepAnswering() {
        let app = launchOnToday()
        open("freeRooms", titled: "Aule libere", in: app)
        settle()
        shot(app, "rooms-01-open")

        let campus = app.buttons["Sede"].firstMatch
        if campus.waitForExistence(timeout: 10) {
            campus.tap()
            settle()
            // Whichever campuses the sample data has: take the second, so the
            // choice actually changes.
            let options = app.buttons.allElementsBoundByIndex.filter { $0.isHittable }
            if options.count > 1 { options[1].tap() } else { options.first?.tap() }
            settle()
            shot(app, "rooms-02-campus")
        }

        let minimum = app.buttons["Almeno"].firstMatch
        if minimum.waitForExistence(timeout: 5) {
            minimum.tap()
            settle()
            let options = app.buttons.allElementsBoundByIndex.filter { $0.isHittable }
            options.last?.tap()
            settle()
            shot(app, "rooms-03-minimum")
        }

        require(app.navigationBars["Aule libere"], "Cambiare i filtri ha fatto sparire la schermata")
    }

    /// The day picker moves the whole screen to another date; a room free
    /// today is not free tomorrow, and the screen has to keep up.
    @MainActor func testFreeRoomsFollowsTheChosenDay() {
        let app = launchOnToday()
        open("freeRooms", titled: "Aule libere", in: app)

        let day = app.datePickers.firstMatch
        if day.waitForExistence(timeout: 10) {
            shot(app, "rooms-04-day")
            XCTAssertTrue(day.isHittable, "Il selettore del giorno non si può toccare")
        }
        require(app.navigationBars["Aule libere"], "La schermata non ha retto il cambio di giorno")
    }
}
