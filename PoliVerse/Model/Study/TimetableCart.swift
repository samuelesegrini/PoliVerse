import Foundation
import Observation
import OSLog

/// The personalised timetable the Manifesti site builds server-side.
///
/// ## Why this is its own module
///
/// It used to be half of ``ManifestiModel``, which carried two `URLSession`s
/// with separate cookie jars — and that was the design saying, in the only way
/// it could, that there were two modules. The catalogue is stateless public
/// reads that cache and parallelise freely; the cart is a *conversation*: the
/// service keeps the timetable against a cookie, so every request here is a
/// step in a sequence, must never be cached, and must never be issued on the
/// authenticated session.
///
/// Splitting them along the sessions makes both statements checkable rather
/// than conventional. Nothing but ``PersonalTimetableModel`` ever spoke to
/// this half, which is what made the seam obvious once it was measured.
///
/// ## The order the service expects
///
/// Its interface is small but it is *not* order-free, and a caller has to know
/// this: ``setName(_:yearCode:)`` comes first, because the site shows the add
/// link and the section choice only once a name is set, and only for that
/// name's bracket. ``sections(for:)`` and ``cartLink(for:)`` then read what
/// that name is allowed to see, and ``addToTimetable(_:link:section:)`` acts
/// on it. ``textTimetable(semester:yearCode:)`` reads the result back.
@Observable
@MainActor
final class TimetableCart {
    /// Teachings in the personalised timetable, as the service reports them.
    private(set) var cartCount = 0
    /// The surname the service is using to pick brackets, once set.
    private(set) var surname: String?

    /// The year the cart defaults to, where a teaching does not name its own.
    ///
    /// Its own, rather than the catalogue's: the year someone is *browsing* in
    /// ``ManifestiModel`` and the year they are *building a timetable for* are
    /// different questions that happened to share a property.
    var year: AcademicYear = AcademicYear.recent().first ?? AcademicYear(code: "2026")

    private let pages: any PageFetching
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "carrello")
    private let base = URL(string: "https://onlineservices.polimi.it/manifesti/manifesti/controller")!

    /// - Parameter pages: the site this cart lives on. Stateful by default —
    ///   the cart *is* the cookie — and swapped for a fixture in tests.
    init(pages: any PageFetching = ScrapedSite.stateful(cookieGroup: "manifesti")) {
        self.pages = pages
    }

    /// Tells the catalogue the surname, which is how it picks the bracket.
    ///
    /// The service asks for "cognome nome" in one field and warns that a
    /// surname alone may resolve the bracket wrongly, so both are sent.
    /// - Parameter yearCode: the timetable's year, when it is not the one the
    ///   catalogue is browsing.
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

    /// Where a teaching's page offers to add it to the cart, read on the
    /// cart's session: the page shows the add link only once a name is set,
    /// and only for that name's bracket.
    func cartLink(for teaching: ManifestoTeaching) async -> PersonalTimetableParser.CartLink? {
        guard let html = await page("ManifestoPublic.do?\(teaching.detailQuery(defaultYear: year.code))") else { return nil }
        return PersonalTimetableParser.cartLink(in: html, code: teaching.code)
    }

    /// The sections a teaching asks the student to choose between, if any.
    ///
    /// Read on the cart's session, like the add link: the page offers the
    /// choice only once a name is set.
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

    /// Empties the personalised timetable.
    func clearTimetable(yearCode: String? = nil) async {
        _ = await page("ManifestoPublic.do?evn_eliminacarrello=evento&aa=\(yearCode ?? year.code)&lang=\(PoliMiLanguage.current.rawValue)&jaf_currentWFID=main")
        cartCount = 0
    }

    /// The "orario testuale" of one semester: the cart as sentences, which
    /// ``PersonalTimetableParser`` reads into slots.
    func textTimetable(semester: Int, yearCode: String? = nil) async -> String? {
        await page("GestioneCarrelloPublic.do?evn_default=EVENTO&tab_selected=2&sel_semestre=\(semester)&sel_aa=\(yearCode ?? year.code)&lang=\(PoliMiLanguage.current.rawValue)&jaf_currentWFID=main")
    }

    // MARK: - Transport

    private func page(_ path: String) async -> String? {
        guard let url = URL(string: "\(base.absoluteString)/\(path)") else { return nil }
        return await pages.page(url)
    }

    private func post(_ path: String, form: [String: String]) async -> String? {
        guard let url = URL(string: "\(base.absoluteString)/\(path)") else { return nil }
        return await pages.post(url, form: form)
    }
}
