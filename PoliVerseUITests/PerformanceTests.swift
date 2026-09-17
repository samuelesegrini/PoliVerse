import XCTest

/// Regression guards for the numbers MetricKit reports from the field.
///
/// Field data arrives a day late and averaged over everyone; these give the
/// same measurements on one simulator or device, before a change ships
/// (`docs/metrickit-performance.md`, Phase 3).
///
/// Run from the **PoliVersePerformance** scheme, which builds Release —
/// numbers from a Debug build describe the debugger, not the app — and keeps
/// these minutes-long runs out of the ordinary test action. Baselines are set
/// in Xcode's test report ("Set Baseline") and kept per device, so a number
/// from a simulator is never compared with one from a phone.
///
/// Every test runs on sample data: no network, no account, the same payload
/// each time. Real endpoints would turn a timing test into a test of the
/// Politecnico's servers.
///
/// The app is launched through ``PoliVerseUITestCase``, which pins the
/// interface and the layout as well as the data. Measuring a screen means
/// first being sure which screen it is: the places that are not tabs live
/// behind Cerca in this interface, and tapping a tab that is not there
/// measures nothing.
nonisolated final class PerformanceTests: PoliVerseUITestCase {
    /// Opens a place from Cerca and waits for its screen.
    @MainActor private func open(_ place: String, titled title: String, in app: XCUIApplication) {
        switchTab(app, to: "Cerca", expecting: "tab-search")
        tap(app.buttons["place-\(place)"].firstMatch, "Cerca non elenca \(title)")
        require(app.navigationBars[title], "\(title) non si è aperta", timeout: 20)
    }

    /// Cold launch until the app responds, including the extended launch task
    /// around session restore — the moment a student can actually use it.
    @MainActor func testLaunch() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            makeApp().launch()
        }
    }

    /// The agenda load, as the `agenda.load` signpost brackets it.
    @MainActor func testAgendaLoad() {
        let metric = XCTOSSignpostMetric(
            subsystem: "one.wape.PoliVerse", category: "PointsOfInterest", name: "agenda.load")
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [metric], options: options) {
            let app = makeApp()
            app.launch()
            // Oggi asks for the agenda; waiting on its bar is enough for the
            // load to have started and, on sample data, ended.
            XCTAssertTrue(app.buttons["today-customize"].firstMatch.waitForExistence(timeout: 30))
            app.terminate()
        }
    }

    /// Hitches while paging the Calendar week strip, the screen the §3.2
    /// finding was about. Apple's guide: under 5 ms/s is good.
    @MainActor func testCalendarWeekPagingHitches() {
        let app = launchOnToday()
        open("calendar", titled: "Calendario", in: app)
        let next = app.buttons["Settimana successiva"].firstMatch
        require(next, "Il calendario non ha il passaggio alla settimana successiva")

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            for _ in 0..<6 { next.tap() }
        }
    }

    /// Hitches while scrolling Oggi, the screen the app opens on.
    @MainActor func testHomeScrollHitches() {
        let app = launchOnToday()
        let scroll = app.scrollViews.firstMatch
        require(scroll, "Oggi non ha niente da scorrere")

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            scroll.swipeUp(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
        }
    }

    /// Hitches while scrolling Corsi, the longest list in the app: one row per
    /// course, each drawing its own colour and star.
    @MainActor func testCoursesScrollHitches() {
        let app = launchOnToday()
        switchTab(app, to: "Corsi", expecting: "tab-courses")
        let list = app.collectionViews.firstMatch
        require(list, "Corsi non ha una lista da scorrere", timeout: 20)

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
    }

    /// What switching tabs costs in work rather than in time: the tab bar
    /// keeps one screen per tab, so a round of the four should not be four
    /// rebuilds.
    @MainActor func testTabSwitchingCost() {
        let app = launchOnToday()

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)],
                options: options) {
            for title in ["Corsi", "Carriera", "Cerca", "Oggi"] {
                tabButton(app, title).tap()
            }
        }
    }

    /// Memory after the walk a student does in the first minute. Kept as its
    /// own measurement because a leak shows here and nowhere else: the timing
    /// tests all end by terminating the app.
    @MainActor func testMemoryAfterAWalkThroughTheApp() {
        let app = launchOnToday()

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTMemoryMetric(application: app)], options: options) {
            switchTab(app, to: "Corsi", expecting: "tab-courses")
            switchTab(app, to: "Carriera", expecting: "tab-career")
            switchTab(app, to: "Cerca", expecting: "tab-search")
            let calendar = app.buttons["place-calendar"].firstMatch
            if calendar.waitForExistence(timeout: 10) {
                calendar.tap()
                _ = app.navigationBars["Calendario"].waitForExistence(timeout: 20)
                goBack(app)
            }
            switchTab(app, to: "Oggi", expecting: "tab-today")
        }
    }
}
