import XCTest

/// Cerca, driven the way a student uses it: type, read the results, open one,
/// come back, clear.
///
/// All of it on sample data, so the courses, teachers and notices searched for
/// here are the ones `MockData` ships.
nonisolated final class SearchUITests: PoliVerseUITestCase {
    /// Selecting the search tab activates its field — `tabViewSearchActivation`
    /// — and the places are listed until something is typed.
    @MainActor func testSearchTabOpensOnTheFieldAndListsPlaces() {
        let app = launchOnToday()
        switchTab(app, to: "Cerca", expecting: "tab-search")

        require(app.searchFields.firstMatch, "Cerca has no search field")
        require(app.buttons["place-calendar"].firstMatch, "Cerca does not list the places before a search")
        shot(app, "search-01-places")
    }

    /// A course name brings the course back, and opening it leads to its
    /// screen. The query is a fragment, not the whole title, because that is
    /// what students type.
    @MainActor func testTypingACourseNameFindsIt() {
        let app = launchOnToday()
        switchTab(app, to: "Cerca", expecting: "tab-search")
        let field = require(app.searchFields.firstMatch, "Cerca has no search field")
        field.tap()
        field.typeText("Basi")
        settle()
        shot(app, "search-02-results")

        let result = app.staticTexts["Basi di Dati"].firstMatch
        require(result, "Searching for “Basi” did not find Basi di Dati")
        XCTAssertFalse(
            app.descendants(matching: .any)["search-empty"].firstMatch.exists,
            "A search with results still showed the empty state")

        result.tap()
        require(app.navigationBars["Basi di Dati"], "Tapping the result did not open the course", timeout: 15)
        shot(app, "search-03-course")
        goBack(app)
        require(app.searchFields.firstMatch, "Going back did not return to Cerca")
    }

    /// A query nothing matches shows the empty state rather than an empty
    /// list, which reads as a failed load.
    @MainActor func testAQueryWithNoResultsShowsTheEmptyState() {
        let app = launchOnToday()
        switchTab(app, to: "Cerca", expecting: "tab-search")
        let field = require(app.searchFields.firstMatch, "Cerca has no search field")
        field.tap()
        field.typeText("zzzqwerty")
        settle()

        require(
            app.descendants(matching: .any)["search-empty"].firstMatch,
            "A search with no results showed no empty state")
        shot(app, "search-04-empty")
    }

    /// Clearing the field puts the places back: the screen returns to where it
    /// started rather than staying on a stale result set.
    @MainActor func testClearingTheQueryBringsThePlacesBack() {
        let app = launchOnToday()
        switchTab(app, to: "Cerca", expecting: "tab-search")
        let field = require(app.searchFields.firstMatch, "Cerca has no search field")
        field.tap()
        field.typeText("Reti")
        settle()

        let clear = app.buttons["Clear text"].firstMatch
        if clear.exists {
            clear.tap()
        } else {
            // The clear button's label follows the system language; typing the
            // deletes is the way in that never depends on it.
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        }
        settle()
        require(app.buttons["place-calendar"].firstMatch, "Clearing the query did not bring the places back")
    }
}
