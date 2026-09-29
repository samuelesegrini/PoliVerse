import XCTest

/// The same measurements as ``PerformanceTests``, on the account signed in on the
/// device rather than on sample data.
///
/// Sample data is small and never touches the offline cache or the network, so it
/// hides exactly the work `docs/metrickit-performance.md` §5 moved off the main
/// thread: a real timetable, a term of updates, a course with hundreds of files.
///
/// Opt-in, three ways over:
///
/// - Only the **PoliVerseRealData** scheme runs this class, and it sets
///   `POLIVERSE_REAL_DATA=1`; every other scheme skips it.
/// - Without that variable each test skips itself, so a stray run measures
///   nothing and asks the Politecnico for nothing.
/// - Nobody signed in on the device is a skip too, naming what to do. Signing in
///   is the student's to do, by hand; no test types a credential.
///
/// What the class promises the student whose phone it runs on:
///
/// - It only reads. The app never writes to the university's systems, and these
///   tests only open screens and scroll them.
/// - It keeps the load light: three iterations, and the refresh it times is the
///   one the app already runs at every launch.
/// - It keeps no pictures. The scheme discards attachments, since a screenshot of
///   Carriera is a screenshot of someone's marks.
///
/// Real data changes from one day to the next, so a comparison between two builds
/// means running them one after the other in the same session, not against a
/// baseline from last week.
nonisolated final class RealDataPerformanceTests: PoliVerseUITestCase {
    /// The subsystem every signpost in the app is filed under.
    private static let subsystem = "segrini.samuele.PoliVerse"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["POLIVERSE_REAL_DATA"] == "1",
            "Real-data measurements run only from the PoliVerseRealData scheme")
    }

    // MARK: Launch

    /// A launched app on the signed-in account, sitting on Oggi.
    ///
    /// - Throws: A skip when nobody is signed in on the device.
    @MainActor private func launchSignedIn() throws -> XCUIApplication {
        let app = makeApp(data: .signedInAccount)
        app.launch()
        if app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 30) { return app }
        if app.buttons["Codice persona e password"].firstMatch.exists {
            throw XCTSkip("Nobody is signed in on this device: sign in to PoliVerse by hand, then run again")
        }
        XCTFail("The app never reached Oggi")
        return app
    }

    /// Cold launch until the app responds, with the real Keychain token and the
    /// real offline copies behind session restore.
    @MainActor func testLaunchOnTheAccount() throws {
        try launchSignedIn().terminate()

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            makeApp(data: .signedInAccount).launch()
        }
    }

    /// How long the offline copies take to read at launch, one `offline.read`
    /// interval per record, next to the session restore they sit behind.
    @MainActor func testOfflineReadsAtLaunch() throws {
        try launchSignedIn().terminate()

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [
            XCTOSSignpostMetric(subsystem: Self.subsystem, category: "PointsOfInterest", name: "offline.read"),
            XCTOSSignpostMetric(subsystem: Self.subsystem, category: "PointsOfInterest", name: "session.restore"),
        ], options: options) {
            let app = makeApp(data: .signedInAccount)
            app.launch()
            XCTAssertTrue(app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 30))
            // The services restore as their screens first ask; Oggi asks for
            // most of them within a few seconds.
            sleep(5)
            app.terminate()
        }
    }

    /// The refresh every launch runs once the session is back: the whole
    /// pass, and the two loads a student waits on.
    @MainActor func testRefreshAfterLaunch() throws {
        try launchSignedIn().terminate()

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [
            XCTOSSignpostMetric(subsystem: Self.subsystem, category: "PointsOfInterest", name: "freshness.revalidate"),
            XCTOSSignpostMetric(subsystem: Self.subsystem, category: "PointsOfInterest", name: "agenda.load"),
            XCTOSSignpostMetric(subsystem: Self.subsystem, category: "PointsOfInterest", name: "career.load"),
        ], options: options) {
            let app = makeApp(data: .signedInAccount)
            app.launch()
            XCTAssertTrue(app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 30))
            // Long enough for the pass to finish on a slow connection.
            sleep(20)
            app.terminate()
        }
    }

    // MARK: Scrolling

    /// Hitches while flicking a scroll view up and down, three times over.
    @MainActor private func measureScrolling(_ scroll: XCUIElement, in app: XCUIApplication) {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            scroll.swipeUp(velocity: .fast)
            scroll.swipeUp(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
        }
    }

    /// The screen's own scroll view, found by its identifier where it carries
    /// one, or else the first on screen.
    @MainActor private func scrollView(_ app: XCUIApplication, tagged identifier: String) -> XCUIElement {
        let tagged = app.scrollViews.matching(identifier: identifier).firstMatch
        let scroll = tagged.waitForExistence(timeout: 5) ? tagged : app.scrollViews.firstMatch
        return require(scroll, "Nothing to scroll on \(identifier)", timeout: 20)
    }

    /// Oggi, with a real day on it.
    @MainActor func testTodayScrolling() throws {
        let app = try launchSignedIn()
        measureScrolling(scrollView(app, tagged: "tab-today"), in: app)
    }

    /// Corsi, one card per real course, each matching its lessons by name.
    @MainActor func testCoursesScrolling() throws {
        let app = try launchSignedIn()
        switchTab(app, to: "Corsi", expecting: "tab-courses")
        measureScrolling(scrollView(app, tagged: "tab-courses"), in: app)
    }

    /// Carriera, with the whole libretto under the cards.
    @MainActor func testCareerScrolling() throws {
        let app = try launchSignedIn()
        switchTab(app, to: "Carriera", expecting: "tab-career")
        measureScrolling(scrollView(app, tagged: "tab-career"), in: app)
    }

    /// The updates feed, a term's worth of sightings folded into rows.
    @MainActor func testUpdatesFeedScrolling() throws {
        let app = try launchSignedIn()
        switchTab(app, to: "Carriera", expecting: "tab-career")
        tap(app.buttons["Novità"].firstMatch, "Carriera has no Novità")
        require(app.navigationBars["Novità esami"], "The updates feed did not open", timeout: 20)
        measureScrolling(app.scrollViews.firstMatch, in: app)
    }

    /// Paging the calendar past the month the app has fetched, which loads each
    /// new week from the Politecnico.
    @MainActor func testCalendarPaging() throws {
        let app = try launchSignedIn()
        tap(app.buttons["today-calendar"].firstMatch, "Oggi has no calendar")
        require(app.navigationBars["Calendario"], "The calendar did not open", timeout: 20)
        let next = require(app.buttons["Settimana successiva"].firstMatch, "The calendar cannot page")

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [
            XCTHitchMetric(application: app),
            XCTOSSignpostMetric(subsystem: Self.subsystem, category: "PointsOfInterest", name: "agenda.load"),
        ], options: options) {
            // Six weeks, past the month each fetch holds, so every iteration
            // loads: weeks already fetched are kept, and an iteration with no
            // `agenda.load` makes XCTest drop the metric for all but the first.
            for _ in 0..<6 { next.tap() }
        }
    }

    /// The materials of the student's biggest course: the list that asked the
    /// disk about every file on every pass before §5.2.
    @MainActor func testBiggestCourseMaterialsScrolling() throws {
        let app = try launchSignedIn()
        let course = try biggestCourse(in: app)
        // Back to Corsi's root: walking every course can leave another screen
        // on top, and the card is only on Corsi's own.
        switchTab(app, to: "Corsi", expecting: "tab-courses")
        openMaterials(of: course, in: app)
        measureScrolling(app.scrollViews.firstMatch, in: app)
    }

    /// Opens every course's materials once and keeps the one with the most files.
    ///
    /// One listing request per course, once per run; read from the hero's
    /// summary, which says "24 file · 1,2 GB".
    ///
    /// - Returns: The identifier of the biggest course's card.
    @MainActor private func biggestCourse(in app: XCUIApplication) throws -> String {
        switchTab(app, to: "Corsi", expecting: "tab-courses")
        // Any element type: a card's row merges its children into one element,
        // and XCUITest does not report it as a button.
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'course-'"))
        guard cards.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("Corsi lists no courses on this account")
        }
        let identifiers = Set(cards.allElementsBoundByIndex.map(\.identifier))
            .filter { $0 != "course-materials" }.sorted()

        var best: (identifier: String, files: Int)?
        for identifier in identifiers {
            // A course seen only on WeBeep can be matched to an official one
            // when the launch refresh lands, and its card takes the official
            // id: one that has gone is skipped, not failed.
            guard reveal(identifier, in: app) else { continue }
            openMaterials(of: identifier, in: app)
            let files = fileCount(in: app)
            goBack(app)
            goBack(app)
            if files > (best?.files ?? -1) { best = (identifier, files) }
        }
        guard let best, best.files > 0 else { throw XCTSkip("No course on this account has materials") }
        return best.identifier
    }

    /// Scrolls Corsi until a course's card is in the tree.
    ///
    /// Favourites are a lazy grid at the top: once the list has scrolled down under
    /// the walk, their tiles are not in the tree until scrolled back into view.
    ///
    /// - Returns: Whether the card is there.
    @MainActor private func reveal(_ course: String, in app: XCUIApplication) -> Bool {
        let card = app.descendants(matching: .any)[course].firstMatch
        if card.waitForExistence(timeout: 5) { return true }
        let list = app.scrollViews.matching(identifier: "tab-courses").firstMatch
        guard list.exists else { return false }
        for _ in 0..<4 where !card.exists { list.swipeDown(velocity: .fast) }
        for _ in 0..<8 where !card.exists { list.swipeUp() }
        return card.exists
    }

    /// From Corsi, opens a course and then its materials.
    @MainActor private func openMaterials(of course: String, in app: XCUIApplication) {
        _ = reveal(course, in: app)
        tap(app.descendants(matching: .any)[course].firstMatch, "Corsi has no card \(course)", timeout: 20)
        tap(app.descendants(matching: .any)["course-materials"].firstMatch, "The course has no Materiali", timeout: 20)
    }

    /// The number of files the materials hero reports, once the listing arrives.
    @MainActor private func fileCount(in app: XCUIApplication) -> Int {
        let summary = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ file.*")).firstMatch
        guard summary.waitForExistence(timeout: 20) else { return 0 }
        return Int(summary.label.prefix { $0.isNumber }) ?? 0
    }

    // MARK: Memory

    /// Memory after the first minute's walk, with real lists in every tab.
    @MainActor func testMemoryAfterAWalk() throws {
        let app = try launchSignedIn()

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTMemoryMetric(application: app)], options: options) {
            switchTab(app, to: "Corsi", expecting: "tab-courses")
            switchTab(app, to: "Carriera", expecting: "tab-career")
            switchTab(app, to: "Cerca", expecting: "tab-search")
            switchTab(app, to: "Oggi", expecting: "tab-today")
        }
    }
}
