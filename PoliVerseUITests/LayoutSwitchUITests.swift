import XCTest

/// Changing the layout from Impostazioni, which is a dance rather than a
/// toggle: the sheet has to close first, then the app animates from the tab
/// bar to the single page (or back), and the shell that owns both has to
/// survive it. Presented from a layout instead of above both, the settings
/// sheet wrote to a stray shell and its dismissal never found the pending
/// change — this walks exactly that path.
nonisolated final class LayoutSwitchUITests: PoliVerseUITestCase {
    @MainActor func testSwitchingToTheSinglePageAndBack() {
        let app = launchOnToday()
        XCTAssertTrue(tabButton(app, "Carriera").exists, "The app did not open on the tab layout")

        choose("Pagina unica", in: app)
        XCTAssertTrue(
            tabButton(app, "Carriera").waitForNonExistence(timeout: 10),
            "Choosing the single page left the tab bar up")
        shot(app, "layout-01-single")

        choose("Tab", in: app)
        require(tabButton(app, "Carriera"), "Choosing Tab did not bring the tab bar back")
        shot(app, "layout-02-tabs")
        require(app.buttons["today-customize"].firstMatch, "The change of layout lost Oggi")
    }

    /// The other half of the same dance: the sheet must actually be gone, not
    /// left behind over the app it just rearranged.
    @MainActor func testTheSettingsSheetClosesOnTheChange() {
        let app = launchOnToday()
        choose("Pagina unica", in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["settings-list"].firstMatch.waitForNonExistence(timeout: 10),
            "Impostazioni stayed up over the new layout")
    }

    /// Opens Impostazioni from whichever bar this layout has, picks a layout
    /// from the menu, and leaves the sheet to close itself.
    @MainActor private func choose(_ layout: String, in app: XCUIApplication) {
        let profile = app.buttons["bar-profile"].firstMatch
        let settings = app.buttons["bar-settings"].firstMatch
        if profile.waitForExistence(timeout: 10) {
            profile.tap()
            goBack(app)  // the profile opens one page in
        } else {
            tap(settings, "Neither bar button is on screen")
        }
        require(app.descendants(matching: .any)["settings-list"].firstMatch, "Impostazioni did not open")

        tap(app.buttons["settings-layout"].firstMatch, "Impostazioni has no layout picker")
        tap(app.buttons[layout].firstMatch, "The layout menu does not offer \(layout)")
        settle(2)
    }
}
