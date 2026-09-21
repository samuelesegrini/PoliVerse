import Foundation
import Testing
@testable import PoliVerse

/// The personalised timetable the Manifesti site keeps against a cookie.
///
/// Untestable until it stopped building its own `URLSession`: it is a scraper,
/// so every one of its methods is "send this, parse what comes back", and
/// there was no way to supply the "what comes back" half.
@Suite("Timetable cart")
@MainActor
struct TimetableCartTests {
    private static func teaching(code: String = "086457", year: String? = "2025") -> ManifestoTeaching {
        ManifestoTeaching(code: code, name: "Analisi", courseCode: "1234", planCode: "PL",
                          idItemOfferta: "IO", idRiga: "IR", semester: "1", year: year,
                          credits: 10, school: nil, degreeCourse: nil)
    }

    // MARK: - The order the service expects

    /// The site shows the add link and the section choice only once a name is
    /// set, and only for that name's bracket. Asking first is not an error the
    /// service reports — it simply answers a page without the link, which is
    /// indistinguishable from "this teaching cannot be added".
    @Test("Before a name is set, there is no surname to pick a bracket with")
    func nameComesFirst() async {
        let cart = TimetableCart(pages: FixturePages())
        #expect(cart.surname == nil)
    }

    @Test("Setting the name tells the service, and remembers it")
    func setNamePostsTheName() async {
        let pages = FixturePages(["ManifestoPublic.do": "<html></html>"])
        let cart = TimetableCart(pages: pages)

        await cart.setName("Rossi Mario", yearCode: "2025")

        #expect(cart.surname == "Rossi Mario")
        let posted = try? #require(await pages.posted.first)
        #expect(posted?.form["cognome"] == "Rossi Mario")
        // Both names, because the service warns that a surname alone may
        // resolve the bracket wrongly.
        #expect(posted?.form["aa"] == "2025")
    }

    /// A blank name would clear the bracket the service is using, so it is not
    /// sent at all.
    @Test("An empty name is not sent")
    func emptyNameIsIgnored() async {
        let pages = FixturePages(["ManifestoPublic.do": "<html></html>"])
        let cart = TimetableCart(pages: pages)

        await cart.setName("   ")

        #expect(cart.surname == nil)
        #expect(await pages.posted.isEmpty)
    }

    // MARK: - Adding

    /// The service answers a small XML document rather than a page.
    @Test("An accepted teaching reports the new count")
    func addReportsTheCount() async {
        let pages = FixturePages([
            "EVN_ADDCART": "<r><success>1</success><num-ins-cart>3</num-ins-cart></r>",
        ])
        let cart = TimetableCart(pages: pages)

        let reply = await cart.addToTimetable(Self.teaching(), link: nil)

        #expect(reply == .added(count: 3))
        #expect(cart.cartCount == 3)
    }

    /// A full cart, or a teaching not offered to this bracket: the service
    /// says why, and the reason is worth keeping rather than flattening to a
    /// silent failure.
    @Test("A refused teaching carries the service's own reason")
    func refusalCarriesTheReason() async {
        let pages = FixturePages([
            "EVN_ADDCART": "<r><error/><desc-error>Carrello pieno</desc-error></r>",
        ])
        let cart = TimetableCart(pages: pages)

        let reply = await cart.addToTimetable(Self.teaching(), link: nil)

        #expect(reply == .refused("Carrello pieno"))
        // The count is untouched: nothing was added.
        #expect(cart.cartCount == 0)
    }

    /// No answer at all is a refusal too, but with nothing to tell the student.
    @Test("An unreachable service is a refusal with no reason")
    func silenceIsARefusal() async {
        let cart = TimetableCart(pages: FixturePages())

        #expect(await cart.addToTimetable(Self.teaching(), link: nil) == .refused(nil))
    }

    /// A teaching that names its own year wins over the cart's: the row came
    /// from a search that knew which edition it was.
    @Test("A teaching's own year is sent, not the cart's")
    func teachingYearWins() async throws {
        let pages = FixturePages(["EVN_ADDCART": "<r><success>1</success><num-ins-cart>1</num-ins-cart></r>"])
        let cart = TimetableCart(pages: pages)
        cart.year = AcademicYear(code: "2030")

        _ = await cart.addToTimetable(Self.teaching(year: "2025"), link: nil)

        let posted = try #require(await pages.posted.first)
        #expect(posted.form["aa"] == "2025")
    }

    @Test("A teaching with no year of its own falls back to the cart's")
    func cartYearIsTheFallback() async throws {
        let pages = FixturePages(["EVN_ADDCART": "<r><success>1</success><num-ins-cart>1</num-ins-cart></r>"])
        let cart = TimetableCart(pages: pages)
        cart.year = AcademicYear(code: "2030")

        _ = await cart.addToTimetable(Self.teaching(year: nil), link: nil)

        let posted = try #require(await pages.posted.first)
        #expect(posted.form["aa"] == "2030")
    }

    // MARK: - Emptying

    @Test("Emptying the cart asks the service and zeroes the count")
    func clearingZeroesTheCount() async throws {
        let pages = FixturePages([
            "EVN_ADDCART": "<r><success>1</success><num-ins-cart>2</num-ins-cart></r>",
            "evn_eliminacarrello": "<html></html>",
        ])
        let cart = TimetableCart(pages: pages)
        _ = await cart.addToTimetable(Self.teaching(), link: nil)
        #expect(cart.cartCount == 2)

        await cart.clearTimetable(yearCode: "2025")

        #expect(cart.cartCount == 0)
        let asked = try #require(await pages.requested.last)
        #expect(asked.absoluteString.contains("evn_eliminacarrello"))
    }

    @Test("The text timetable is read per semester")
    func textTimetableAsksPerSemester() async throws {
        let pages = FixturePages(["GestioneCarrelloPublic.do": "<html>orario</html>"])
        let cart = TimetableCart(pages: pages)

        let html = await cart.textTimetable(semester: 2, yearCode: "2025")

        #expect(html == "<html>orario</html>")
        let asked = try #require(await pages.requested.last)
        #expect(asked.absoluteString.contains("sel_semestre=2"))
        #expect(asked.absoluteString.contains("sel_aa=2025"))
    }
}
