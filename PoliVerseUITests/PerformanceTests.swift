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
/// `nonisolated` against the project's main-actor default, which XCTest's
/// initialisers do not share; the tests themselves drive UI and stay on it.
nonisolated final class PerformanceTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Sample data, onboarding done, Italian: the tab and button labels below
    /// are the Italian ones. All three are read from the argument domain of
    /// `UserDefaults`, so the app needs no test-only code. Written as plist
    /// booleans: `Session` reads the flag with `as? Bool`, which a plain `YES`
    /// — a string in that domain — does not satisfy.
    @MainActor private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-useMockData", "<true/>",
            "-hasCompletedOnboarding", "<true/>",
            "-AppleLanguages", "(it)",
            "-AppleLocale", "it_IT",
        ]
        return app
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
            // The Home screen asks for the agenda; waiting on the tab bar is
            // enough for the load to have started and, on sample data, ended.
            XCTAssertTrue(app.buttons["Calendario"].firstMatch.waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    /// Hitches while paging the Calendar week strip, the screen the §3.2
    /// finding was about. Apple's guide: under 5 ms/s is good.
    @MainActor func testCalendarWeekPagingHitches() {
        let app = makeApp()
        app.launch()
        app.buttons["Calendario"].firstMatch.tap()
        let next = app.buttons["Settimana successiva"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 10))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            for _ in 0..<6 { next.tap() }
        }
    }

    /// Hitches while scrolling the Home screen.
    @MainActor func testHomeScrollHitches() {
        let app = makeApp()
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))

        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTHitchMetric(application: app)], options: options) {
            scroll.swipeUp(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
        }
    }
}
