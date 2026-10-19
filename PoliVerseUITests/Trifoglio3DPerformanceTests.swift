import XCTest

/// The 3D walk as a student meets it: how soon the campus appears, what a still campus
/// costs in CPU and memory (the battery's share), and whether the flight to a classroom
/// stutters.
///
/// The walk is a Debug-only prototype opened with `-Trifoglio3D`, so these run from the
/// **PoliVerseUI** scheme (Debug), not PoliVersePerformance, and only with
/// `TRIFOGLIO3D_BENCH=1` in the test action's environment. Run them on a phone: the
/// simulator draws with the Mac's GPU. The goals are in
/// `prototypes/trifoglio-3d-PROTOTYPE/banco/README.md`; `PoliVerseTests/Trifoglio3DLoadTests`
/// times the loading steps one by one.
nonisolated final class Trifoglio3DPerformanceTests: PoliVerseUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TRIFOGLIO3D_BENCH"] == "1",
                          "Banco 3D spento: TRIFOGLIO3D_BENCH=1 per farlo girare")
    }

    /// The button that walks the whole way, there once the campus is on screen.
    private static let tour = "Portami all'aula T.1.2"

    /// The app opened on the 3D walk.
    @MainActor private func makeWalk() -> XCUIApplication {
        let app = makeApp()
        app.launchArguments.append("-Trifoglio3D")
        return app
    }

    /// Launch until the campus is drawn, as the `trifoglio3d.campus` signpost brackets it.
    /// Goal: under 1 s on an iPhone 15.
    @MainActor func testTimeToCampus() {
        let campus = XCTOSSignpostMetric(
            subsystem: "segrini.samuele.PoliVerse", category: "PointsOfInterest", name: "trifoglio3d.campus")
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [campus, XCTClockMetric()], options: options) {
            let app = makeWalk()
            app.launch()
            require(app.buttons[Self.tour], "Il campus 3D non è comparso", timeout: 60)
            app.terminate()
        }
    }

    /// Ten seconds looking at the still campus: CPU and memory of the app alone.
    /// Goal: under 15 % CPU on average, under 300 MB.
    @MainActor func testStillCampus() {
        let app = makeWalk()
        app.launch()
        require(app.buttons[Self.tour], "Il campus 3D non è comparso", timeout: 60)
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            _ = XCTWaiter().wait(for: [XCTestExpectation(description: "fermo")], timeout: 10)
        }
    }

    /// The flight from the campus to classroom T.1.2: hitches, CPU and memory, including
    /// the building's floors read on the way. Goal: under 5 ms of hitches per second.
    @MainActor func testTourToClassroom() {
        let app = makeWalk()
        app.launch()
        let tour = require(app.buttons[Self.tour], "Il campus 3D non è comparso", timeout: 60)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        options.invocationOptions = [.manuallyStart]
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app),
                          XCTMemoryMetric(application: app)], options: options) {
            // Each run starts back on the campus.
            let campus = app.buttons["Campus"].firstMatch
            if campus.exists, campus.isEnabled {
                campus.tap()
                _ = tour.waitForExistence(timeout: 10)
            }
            startMeasuring()
            tour.tap()
            require(app.buttons["Entra nell'aula"], "La camera non è arrivata all'aula", timeout: 30)
        }
    }
}
