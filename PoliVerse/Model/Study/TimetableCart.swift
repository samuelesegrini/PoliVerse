import Foundation
import Observation
import OSLog

/// The personalised timetable the Manifesti site builds server-side.
///
/// A conversation rather than a set of reads: the service keeps the timetable against a
/// cookie, so every request here is a step in a sequence, must never be cached, and must
/// never be issued on the authenticated session. The catalogue half — stateless public
/// reads that cache and parallelise freely — is ``ManifestiModel``'s.
///
/// ## The order the service expects
///
/// ``setName(_:yearCode:)`` comes first, because the site shows the add link and the
/// section choice only once a name is set, and only for that name's bracket.
/// ``sections(for:)`` and ``cartLink(for:)`` then read what that name is allowed to see,
/// ``addToTimetable(_:link:section:)`` acts on it, and
/// ``textTimetable(semester:yearCode:)`` reads the result back.
///
/// ``PersonalTimetableModel`` is the only caller.
@Observable
@MainActor
final class TimetableCart {
    /// How many teachings the service reports in the cart.
    private(set) var cartCount = 0
    /// The name the service is using to pick brackets, once ``setName(_:yearCode:)`` has been
    /// called. `nil` before that, which is why the add link cannot be read yet.
    private(set) var surname: String?

    /// The year the cart works in, where a teaching does not name its own.
    ///
    /// Its own rather than the catalogue's: the year someone is browsing and the year they
    /// are building a timetable for are different questions.
    var year: AcademicYear = AcademicYear.recent().first ?? AcademicYear(code: "2026")

    /// The site this cart lives on.
    private let pages: any PageFetching
    /// Diagnostic log for this type, under the `carrello` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "carrello")
    /// The controller every request goes to.
    private let base = URL(string: "https://onlineservices.polimi.it/manifesti/manifesti/controller")!

    /// Creates the cart.
    ///
    /// - Parameter pages: The site it lives on. Stateful by default, because the cart is the
    ///   cookie; swapped for a fixture in tests.
    init(pages: any PageFetching = ScrapedSite.stateful(cookieGroup: "manifesti")) {
        self.pages = pages
    }

    /// Tells the service the name, which is how it picks the alphabetical bracket.
    ///
    /// Setting a name empties the cart. The service asks for surname and forename in one
    /// field and warns that a surname alone may resolve the bracket wrongly, so both are
    /// sent. A blank name does nothing.
    ///
    /// - Parameters:
    ///   - fullName: Surname and forename, as the service wants them.
    ///   - yearCode: The timetable's year, when it is not ``year``.
    func setName(_ fullName: String, yearCode: String? = nil) async {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let aa = yearCode ?? year.code
        _ = await page("ManifestoPublic.do?evn_gointrocarrello=evento&aa=\(aa)&lang=\(PoliMiLanguage.current.rawValue)&jaf_currentWFID=main")
        _ = await post("ManifestoPublic.do", form: [
            "evn_setcognome": "Imposta cognome e nome",
            "cognome": trimmed,
            "aa": aa,
            "lang": PoliMiLanguage.current.rawValue,
            "c_accordo": "",
        ])
        surname = trimmed
        log.notice("manifesti: scaglione impostato")
    }

    /// Where a teaching's page offers to add it to the cart.
    ///
    /// Read on the cart's own session: the page shows the add link only once a name is set,
    /// and only for that name's bracket.
    ///
    /// - Parameter teaching: The teaching to add.
    /// - Returns: The link, or `nil` when the page carries none.
    func cartLink(for teaching: ManifestoTeaching) async -> PersonalTimetableParser.CartLink? {
        guard let html = await page("ManifestoPublic.do?\(teaching.detailQuery(defaultYear: year.code))") else { return nil }
        return PersonalTimetableParser.cartLink(in: html, code: teaching.code)
    }

    /// The sections a teaching asks the student to choose between.
    ///
    /// Read on the cart's own session, like the add link. The dialog needs the school, which
    /// the page writes into its own script.
    ///
    /// - Parameter teaching: The teaching to ask about.
    /// - Returns: The link and the sections, or `nil` when the teaching is not offered in
    ///   sections or the fragment could not be read.
    func sections(for teaching: ManifestoTeaching)
        async -> (link: PersonalTimetableParser.SectionsLink, options: [PersonalTimetableParser.SectionOption])? {
        guard let html = await page("ManifestoPublic.do?\(teaching.detailQuery(defaultYear: year.code))"),
              let link = PersonalTimetableParser.sectionsLink(in: html, code: teaching.code) else { return nil }
        // The dialog's school, which the page writes into its own script.
        let school = HTMLScraper.firstMatch(#"k_cf:\s*([0-9]+)"#, in: html, group: 1) ?? "-1"
        var components = URLComponents()
        components.queryItems = [
            .init(name: "evn_showsezioni", value: "evento"), .init(name: "aa", value: teaching.year ?? year.code),
            .init(name: "k_cf", value: school), .init(name: "k_corso_la", value: link.courseCode),
            .init(name: "k_indir", value: link.planCode), .init(name: "codDescr", value: teaching.code),
            .init(name: "ac_ins", value: link.yearOfCourse), .init(name: "idItemOfferta", value: link.idItemOfferta),
            .init(name: "idGruppo", value: link.idGruppo), .init(name: "idRiga", value: link.idRiga),
            .init(name: "lang", value: PoliMiLanguage.current.rawValue),
        ]
        guard let fragment = await page("ManifestoPublic.do?\(components.percentEncodedQuery ?? "")") else { return nil }
        let options = PersonalTimetableParser.sections(fragment)
        return options.isEmpty ? nil : (link, options)
    }

    /// Adds a teaching to the personalised timetable.
    ///
    /// Answers a small XML document rather than a page: `<success>` with the
    /// new count, or `<error>` with the reason — a full cart, a teaching not
    /// offered to this bracket.
    func addToTimetable(
        _ teaching: ManifestoTeaching, link: PersonalTimetableParser.CartLink?, section: String = ""
    ) async -> PersonalTimetableParser.CartReply {
        guard let xml = await post("ManifestoPublic.do?EVN_ADDCART=EVENTO", form: [
            "aa": teaching.year ?? year.code,
            "k_corso_la": link?.courseCode ?? teaching.courseCode,
            "k_indir": link?.planCode ?? teaching.planCode ?? "",
            "codDescr": teaching.code,
            // The year of course, as the page's own script sends it.
            "ac_ins": link?.yearOfCourse ?? "0",
            "semestre": link?.semester ?? teaching.semester ?? "",
            "sezione": section,
            "lang": PoliMiLanguage.current.rawValue,
        ]) else { return .refused(nil) }
        let reply = PersonalTimetableParser.cartReply(xml)
        if case .added(let count) = reply { cartCount = count }
        return reply
    }

    /// Empties the cart.
    ///
    /// - Parameter yearCode: The timetable's year, when it is not ``year``.
    func clearTimetable(yearCode: String? = nil) async {
        _ = await page("ManifestoPublic.do?evn_eliminacarrello=evento&aa=\(yearCode ?? year.code)&lang=\(PoliMiLanguage.current.rawValue)&jaf_currentWFID=main")
        cartCount = 0
    }

    /// The orario testuale of one semester: the cart written out as sentences, which
    /// ``PersonalTimetableParser/entries(_:)`` reads into slots.
    ///
    /// - Parameters:
    ///   - semester: 1 or 2.
    ///   - yearCode: The timetable's year, when it is not ``year``.
    /// - Returns: The page, or `nil` when it could not be read.
    func textTimetable(semester: Int, yearCode: String? = nil) async -> String? {
        await page("GestioneCarrelloPublic.do?evn_default=EVENTO&tab_selected=2&sel_semestre=\(semester)&sel_aa=\(yearCode ?? year.code)&lang=\(PoliMiLanguage.current.rawValue)&jaf_currentWFID=main")
    }

    // MARK: - Transport

    /// Fetches a page below the controller.
    ///
    /// - Parameter path: The path and query.
    /// - Returns: The markup, or `nil`.
    private func page(_ path: String) async -> String? {
        guard let url = URL(string: "\(base.absoluteString)/\(path)") else { return nil }
        return await pages.page(url)
    }

    /// Posts a form to a path below the controller.
    ///
    /// - Parameters:
    ///   - path: The path.
    ///   - form: The form fields.
    /// - Returns: The markup, or `nil`.
    private func post(_ path: String, form: [String: String]) async -> String? {
        guard let url = URL(string: "\(base.absoluteString)/\(path)") else { return nil }
        return await pages.post(url, form: form)
    }
}
