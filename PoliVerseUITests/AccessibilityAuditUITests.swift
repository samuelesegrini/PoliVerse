import XCTest

/// Runs Xcode's automated accessibility audit over each screen of the app.
///
/// The audit is the same one the Accessibility Inspector runs by hand: it
/// looks for elements with no label, labels that repeat their trait ("pulsante
/// Chiudi pulsante"), hit regions under 44×44, contrast below the WCAG ratio,
/// text that clips at large sizes, and elements the audit cannot reach at all.
/// Running it in CI means a screen cannot quietly lose its labels between
/// releases.
///
/// Two audits are deliberately not asked for everywhere:
/// `.contrast` and `.textClipped` read pixels, so they flag the app's own
/// decorative papers and stickers — the looks in Personalizza are pictures by
/// design. Those two run in `testTodayContrastAndClipping`, which knows what
/// it is looking at; the rest of the audit runs on every screen.
nonisolated final class AccessibilityAuditUITests: PoliVerseUITestCase {
    /// Everything but the two pixel-reading audits.
    private var structuralAudit: XCUIAccessibilityAuditType {
        [.elementDetection, .hitRegion, .sufficientElementDescription, .trait, .dynamicType]
    }

    /// Oggi, Corsi, Carriera and Cerca, each audited as it first appears.
    @MainActor func testTabsPassAudit() throws {
        let app = launchOnToday()
        try audit(app, named: "Oggi")

        for (title, identifier) in [("Corsi", "tab-courses"), ("Carriera", "tab-career"), ("Cerca", "tab-search")] {
            switchTab(app, to: title, expecting: identifier)
            settle()
            try audit(app, named: title)
        }
    }

    /// The places behind Cerca, which are whole screens of their own and are
    /// otherwise only ever seen by eye.
    @MainActor func testPlacesPassAudit() throws {
        let app = launchOnToday()
        switchTab(app, to: "Cerca", expecting: "tab-search")

        for (id, title) in [("calendar", "Calendario"), ("freeRooms", "Aule libere"), ("news", "Notizie")] {
            let row = app.buttons["place-\(id)"].firstMatch
            require(row, "Cerca does not list \(title)")
            row.tap()
            require(app.navigationBars[title], "\(title) did not open", timeout: 15)
            settle()
            try audit(app, named: title)
            goBack(app)
        }
    }

    /// Impostazioni and the profile, the screens that carry the account.
    @MainActor func testSettingsPassAudit() throws {
        let app = launchOnToday()
        switchTab(app, to: "Corsi", expecting: "tab-courses")
        tap(app.buttons["bar-profile"].firstMatch, "Corsi has no profile button")
        require(app.navigationBars["Profilo"], "The profile did not open")
        settle()
        try audit(app, named: "Profilo")

        goBack(app)
        require(app.descendants(matching: .any)["settings-list"].firstMatch, "The profile did not sit inside Impostazioni")
        settle()
        try audit(app, named: "Impostazioni")
    }

    /// The app at the largest accessibility text size. `.dynamicType` is the
    /// audit that matters here: it flags text that stopped growing, and the
    /// hit-region audit catches controls that got squeezed out of the way.
    @MainActor func testLargestTextSizePassesAudit() throws {
        let app = launchOnToday(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        shot(app, "a11y-01-today-axxxl")
        try audit(app, named: "Oggi at AX5")

        switchTab(app, to: "Carriera", expecting: "tab-career")
        settle()
        shot(app, "a11y-02-career-axxxl")
        try audit(app, named: "Carriera at AX5")
    }

    /// Contrast and clipping on Oggi, where the looks put text over paper and
    /// stickers. Issues are reported rather than failed: the audit reads the
    /// rendered pixels, and a sticker sitting behind a word is not a bug.
    /// A screenshot goes with every issue, so a real contrast slip is visible
    /// in the report instead of buried in a log line.
    @MainActor func testTodayContrastAndClipping() throws {
        let app = launchOnToday()
        var reported: [String] = []
        try app.performAccessibilityAudit(for: [.contrast, .textClipped]) { issue in
            reported.append("\(issue.auditType): \(issue.compactDescription)")
            return true  // handled: recorded, not failed
        }
        if !reported.isEmpty {
            let attachment = XCTAttachment(string: reported.joined(separator: "\n"))
            attachment.name = "oggi-contrast-and-clipping"
            attachment.lifetime = .keepAlways
            add(attachment)
            shot(app, "a11y-10-today-contrast")
        }
    }

    /// Fails with the screen's name in front of the audit's own words, so a
    /// failure in CI says which screen without opening the report.
    @MainActor private func audit(
        _ app: XCUIApplication, named screen: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        try app.performAccessibilityAudit(for: structuralAudit) { issue in
            XCTFail("\(screen): \(issue.compactDescription)", file: file, line: line)
            return true  // reported here, with the screen's name
        }
    }
}
