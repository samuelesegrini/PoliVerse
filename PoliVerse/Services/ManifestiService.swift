import Foundation
import Observation
import OSLog

/// The Manifesti degli Studi: the public course catalogue.
///
/// Public and unauthenticated, and HTML only — there is no API. Every request
/// here is a page fetch and a parse, which is why the parsing lives apart in
/// ``ManifestoParser`` where it can be tested against saved markup.
///
/// ## Why this is worth scraping
///
/// It answers what the authenticated services cannot: what a teaching covers,
/// which books it uses, who lectures which alphabetical bracket, and what all
/// of that looks like *before* enrolling. The **scaglione** in particular —
/// the surname bracket that decides a first-year student's lecturer and
/// timetable — appears nowhere else.
///
/// ## Session
///
/// The personalised timetable is server-side state keyed to a cookie, so this
/// keeps its own cookie jar rather than borrowing the app's: nothing here
/// should be able to disturb the authenticated session, and the catalogue
/// never needs to know who the student is.
@Observable
final class ManifestiService {
    private(set) var results: [ManifestoTeaching] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    /// Teachings in the personalised timetable, as the service reports them.
    private(set) var cartCount = 0
    /// The surname the catalogue is using to pick brackets, once set.
    private(set) var surname: String?

    var year: AcademicYear = AcademicYear.recent().first ?? AcademicYear(code: "2026")

    private let session: URLSession
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "manifesti")
    private let base = URL(string: "https://onlineservices.polimi.it/manifesti/manifesti/controller")!
    private let syllabusBase = URL(string:
        "https://onlineservices.polimi.it/schedaincarico/schedaincarico/controller/scheda_pubblica/SchedaPublic.do")!

    private let detailLoader: ResourceLoader<String, ManifestoDetail>
    private let syllabusLoader: ResourceLoader<String, Syllabus>

    init() {
        // Its own cookie jar: the cart is server-side state on a cookie, and
        // it must not be able to touch the authenticated session.
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: "manifesti")
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        let session = URLSession(configuration: configuration)
        self.session = session

        let base = self.base
        detailLoader = ResourceLoader(lifetime: .seconds(3600), capacity: 64) { key in
            guard let url = URL(string: "\(base.absoluteString)/ManifestoPublic.do?\(key)"),
                  let html = await Self.page(url, session: session)
            else { return nil }
            let code = HTMLScraper.queryValue("codDescr", in: key) ?? ""
            return ManifestoParser.detail(html, code: code)
        }

        let syllabusBase = self.syllabusBase
        syllabusLoader = ResourceLoader(lifetime: .seconds(86400), capacity: 128) { classID in
            var components = URLComponents(url: syllabusBase, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                .init(name: "evn_default", value: "evento"),
                .init(name: "c_classe", value: classID),
                .init(name: "lang", value: PoliMiLanguage.current.rawValue),
            ]
            guard let url = components.url,
                  let html = await Self.page(url, session: session)
            else { return nil }
            let parsed = ManifestoParser.syllabus(html)
            // An empty parse is a failure, not an answer: the service returns
            // its search page when a class id is unknown, and caching that as
            // "this teaching has no syllabus" would be wrong.
            return parsed.isEmpty ? nil : parsed
        }
    }

    // MARK: - Search

    func search(_ query: String, school: String? = nil, semester: String? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            results = []
            return
        }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        var form = [
            "evn_default": "Esegui Ricerca",
            "aa": year.code,
            "k_cf": school ?? "-1",
            "sede": "ALL_SEDI",
            "tipoCorso": "ALL_TIPO_CORSO",
            "ac_ins": "0",
            "semestre": semester ?? "ALL_SEMESTRI",
            "aree": "-1",
            "tipoInsegnamento": "ALL_TIPO_INSEGNAMENTO",
            "insegn_ricerca": trimmed,
            "lang": PoliMiLanguage.current.rawValue,
        ]
        form["jaf_currentWFID"] = "main"

        guard let html = await post(
            "ricerche/RicercaPerInsegnamentoPublic.do", form: form)
        else {
            errorMessage = String(localized: "Il catalogo del Politecnico non ha risposto.")
            return
        }
        results = ManifestoParser.searchResults(html)
        log.notice("manifesti: \(self.results.count, privacy: .public) insegnamenti per «\(trimmed, privacy: .public)»")
    }

    // MARK: - Detail and syllabus

    func detail(for teaching: ManifestoTeaching) async -> ManifestoDetail? {
        await detailLoader.value(for: detailQuery(teaching))
    }

    func prefetchDetails(_ teachings: some Sequence<ManifestoTeaching>) {
        let keys = teachings.map(detailQuery)
        Task.detached(priority: .background) { [detailLoader] in
            await detailLoader.prefetch(keys)
        }
    }

    func syllabus(for classID: String) async -> Syllabus? {
        await syllabusLoader.value(for: classID)
    }

    private func detailQuery(_ teaching: ManifestoTeaching) -> String {
        var items = [
            URLQueryItem(name: "EVN_DETTAGLIO_RIGA_MANIFESTO", value: "evento"),
            URLQueryItem(name: "k_corso_la", value: teaching.courseCode),
            URLQueryItem(name: "codDescr", value: teaching.code),
            URLQueryItem(name: "aa", value: teaching.year ?? year.code),
            URLQueryItem(name: "lang", value: PoliMiLanguage.current.rawValue),
            URLQueryItem(name: "jaf_currentWFID", value: "main"),
        ]
        if let plan = teaching.planCode { items.append(.init(name: "k_indir", value: plan)) }
        if let item = teaching.idItemOfferta { items.append(.init(name: "idItemOfferta", value: item)) }
        if let riga = teaching.idRiga { items.append(.init(name: "idRiga", value: riga)) }
        if let semester = teaching.semester { items.append(.init(name: "semestre", value: semester)) }

        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }

    // MARK: - Personalised timetable

    /// Tells the catalogue the surname, which is how it picks the bracket.
    ///
    /// The service asks for "cognome nome" in one field and warns that a
    /// surname alone may resolve the bracket wrongly, so both are sent.
    func setName(_ fullName: String) async {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = await page("ManifestoPublic.do?evn_gointrocarrello=evento&aa=\(year.code)&lang=\(PoliMiLanguage.current.rawValue)&jaf_currentWFID=main")
        _ = await post("ManifestoPublic.do", form: [
            "evn_setcognome": "Imposta cognome e nome",
            "cognome": trimmed,
            "aa": year.code,
            "lang": PoliMiLanguage.current.rawValue,
            "c_accordo": "",
        ])
        surname = trimmed
        log.notice("manifesti: scaglione impostato")
    }

    /// Adds a teaching to the personalised timetable.
    ///
    /// Answers a small XML document rather than a page: `<success>` with the
    /// new count, or `<error>`. Parsed for the count so the UI can show it
    /// without refetching the cart.
    @discardableResult
    func addToTimetable(_ teaching: ManifestoTeaching, section: String = "") async -> Bool {
        await cartCall("EVN_ADDCART", teaching: teaching, section: section)
    }

    @discardableResult
    func removeFromTimetable(_ teaching: ManifestoTeaching, section: String = "") async -> Bool {
        await cartCall("EVN_DELCART", teaching: teaching, section: section)
    }

    private func cartCall(
        _ event: String, teaching: ManifestoTeaching, section: String
    ) async -> Bool {
        guard let xml = await post("ManifestoPublic.do?\(event)=EVENTO", form: [
            "aa": teaching.year ?? year.code,
            "k_corso_la": teaching.courseCode,
            "k_indir": teaching.planCode ?? "",
            "codDescr": teaching.code,
            "ac_ins": "0",
            "semestre": teaching.semester ?? "",
            "sezione": section,
            "lang": PoliMiLanguage.current.rawValue,
        ]) else { return false }

        if let count = HTMLScraper.firstMatch(
            "<num-ins-cart>([0-9]+)</num-ins-cart>", in: xml, group: 1),
           let value = Int(count) {
            cartCount = value
        }
        let ok = xml.contains("<success>")
        if !ok {
            log.error("manifesti: \(event, privacy: .public) rifiutato")
        }
        return ok
    }

    /// Empties the personalised timetable.
    func clearTimetable() async {
        _ = await page("ManifestoPublic.do?evn_eliminacarrello=evento&aa=\(year.code)&lang=\(PoliMiLanguage.current.rawValue)&jaf_currentWFID=main")
        cartCount = 0
    }

    /// The timetable page itself, as the catalogue renders it.
    ///
    /// Returned as a URL rather than parsed: the weekly grid is a layout, not
    /// data, and for 2026/27 the slots are not published yet. Showing the real
    /// page is honest where inventing a grid from nothing would not be.
    var timetableURL: URL {
        URL(string: "\(base.absoluteString)/GestioneCarrelloPublic.do?EVN_DEFAULT=evento&aa=\(year.code)&lang=\(PoliMiLanguage.current.rawValue)&jaf_currentWFID=main")!
    }

    // MARK: - Transport

    private func page(_ path: String) async -> String? {
        guard let url = URL(string: "\(base.absoluteString)/\(path)") else { return nil }
        return await Self.page(url, session: session)
    }

    private static func page(_ url: URL, session: URLSession) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // The service varies its output by language, and asks in Italian by
        // default only when told to.
        request.setValue(PoliMiLanguage.current.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return Self.decode(data)
        } catch {
            return nil
        }
    }

    private func post(_ path: String, form: [String: String]) async -> String? {
        guard let url = URL(string: "\(base.absoluteString)/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(PoliMiLanguage.current.acceptLanguage, forHTTPHeaderField: "Accept-Language")

        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return Self.decode(data)
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            log.error("manifesti: \(path, privacy: .public) fallito: \(error.localizedDescription)")
            return nil
        }
    }

    /// The pages declare UTF-8 and mostly mean it, but some are ISO-8859-1 —
    /// a wrong guess turns every accented letter into a replacement character
    /// across a page that is almost entirely prose.
    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\u{FFFD}") {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1)
    }
}
