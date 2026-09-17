import XCTest

/// The two screens with the student's own data in them: Corsi and Carriera.
///
/// Navigation is covered elsewhere; what these walk is the content — a course
/// opened from the list, the three sections of Carriera — on each area's own
/// `Samples.swift`, so the names looked for here are fixed.
nonisolated final class ContentScreensUITests: PoliVerseUITestCase {
    /// Corsi lists the courses and each one opens. The list is the way into
    /// materials, notices and sittings, so an empty list is the app's worst
    /// failure short of not launching.
    @MainActor func testCoursesListOpensACourse() {
        let app = launchOnToday()
        switchTab(app, to: "Corsi", expecting: "tab-courses")

        let course = app.staticTexts["Ingegneria del Software"].firstMatch
        require(course, "Corsi does not list the sample courses", timeout: 15)
        shot(app, "content-01-courses")

        course.tap()
        require(app.navigationBars["Ingegneria del Software"], "Tapping a course did not open it", timeout: 15)
        shot(app, "content-02-course")

        goBack(app)
        require(app.staticTexts["Ingegneria del Software"].firstMatch, "Going back did not return to the list")
    }

    /// Carriera's three sections each come up with something in them.
    @MainActor func testCareerSectionsEachShowSomething() {
        let app = launchOnToday()
        switchTab(app, to: "Carriera", expecting: "tab-career")

        let sections = app.segmentedControls["Sezione"].firstMatch
        require(sections, "Carriera has no section picker", timeout: 15)

        for section in ["Riepilogo", "Appelli", "Esiti"] {
            let button = sections.buttons[section]
            require(button, "Carriera has no \(section) section")
            button.tap()
            settle()
            shot(app, "content-03-career-\(section.lowercased())")
            XCTAssertTrue(
                button.isSelected,
                "Tapping \(section) did not select it")
            XCTAssertGreaterThan(
                app.staticTexts.count, 1,
                "\(section) came up with nothing on it")
        }
    }

    /// Oggi is the screen the app opens on, and the one a student looks at
    /// every morning: it has to carry the day and a way to change it.
    @MainActor func testTodayShowsTheDayAndItsControls() {
        let app = launchOnToday()

        require(app.buttons["today-customize"].firstMatch, "Oggi has no Personalizza button")
        XCTAssertTrue(
            app.buttons["bar-profile"].firstMatch.exists || app.buttons["bar-settings"].firstMatch.exists,
            "Oggi's bar has neither the profile nor Impostazioni")

        // Scrolling is the whole interaction on Oggi; it must not empty out.
        let scroll = app.scrollViews.firstMatch
        if scroll.waitForExistence(timeout: 10) {
            scroll.swipeUp(velocity: .fast)
            settle()
            shot(app, "content-04-today-scrolled")
            scroll.swipeDown(velocity: .fast)
            settle()
        }
        require(app.buttons["today-customize"].firstMatch, "Scrolling Oggi lost its bar")
    }
}
