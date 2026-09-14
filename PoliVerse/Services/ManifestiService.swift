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

    /// The cart's session: its cookie is the personalised timetable.
    private let session: URLSession
    /// Catalogue reads: no cookies at all. The service serialises requests
    /// that share a `JSESSIONID`, so eight "parallel" detail pages on the
    /// cart's session took eight times as long as one.
    private let catalogue: URLSession
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
        // Never from a cache: every page on this session is the cart's state
        // at this moment. A cached GET turned "empty the cart" into a no-op
        // and returned an old timetable in place of the one just built.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)

        let reads = URLSessionConfiguration.default
        reads.httpCookieStorage = nil
        reads.httpShouldSetCookies = false
        reads.httpCookieAcceptPolicy = .never
        reads.requestCachePolicy = .returnCacheDataElseLoad
        let session = URLSession(configuration: reads)
        self.catalogue = session

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
            // A scheda changes at most once a year: a stored copy younger than
            // a week is the answer, without a page.
            let stored = "syllabus-\(classID)-\(PoliMiLanguage.current.rawValue)"
            let cached = DiskCache.load(Syllabus.self, as: stored)
            if let cached, cached.isFresh(within: Self.storedLifetime) { return cached.value }
            var components = URLComponents(url: syllabusBase, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                .init(name: "evn_default", value: "evento"),
                .init(name: "c_classe", value: classID),
                .init(name: "lang", value: PoliMiLanguage.current.rawValue),
            ]
            guard let url = components.url,
                  let html = await Self.page(url, session: session)
            else { return cached?.value }   // offline: last week's scheda beats none
            let parsed = ManifestoParser.syllabus(html)
            // An empty parse is a failure, not an answer: the service returns
            // its search page when a class id is unknown, and caching that as
            // "this teaching has no syllabus" would be wrong.
            guard !parsed.isEmpty else { return cached?.value }
            DiskCache.save(parsed, as: stored)
            return parsed
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
            "ricerche/RicercaPerInsegnamentoPublic.do", form: form, session: catalogue)
        else {
            errorMessage = String(localized: "Il catalogo del Politecnico non ha risposto.")
            return
        }
        results = ManifestoParser.searchResults(html)
        log.notice("manifesti: \(self.results.count, privacy: .public) insegnamenti per «\(trimmed, privacy: .public)»")
    }

    // MARK: - A student's own teaching

    /// The scheda of one of the student's own teachings, found from its code.
    ///
    /// A code search returns one row per degree course and plan; the details
    /// of a few distinct degree courses are read (cached), and
    /// ``SyllabusPicker`` chooses by the student's degree and surname. Does
    /// not touch ``results``: that is the search screen's state.
    /// - Parameter yearCode: the academic year the course belongs to, e.g.
    ///   `2025` for 2025/26 — last year's course has last year's scheda.
    func syllabusPick(teachingCode: String, surname: String?, degreeName: String?,
                      yearCode: String? = nil) async -> SyllabusPicker.Pick? {
        guard teachingCode.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else { return nil }
        let key = [teachingCode, surname ?? "", degreeName ?? "", yearCode ?? year.code].joined(separator: "|")
        // Kept for the session, found or not: the course page and the exam
        // sheet ask for the same teaching, and each answer costs up to nine
        // pages.
        if let cached = picks[key] { return cached }
        // Found on an earlier launch: shown at once, looked up again only
        // once it is a week old.
        if let stored = await Self.storedPick(key), stored.isFresh(within: Self.storedLifetime) {
            picks[key] = stored.value
            return stored.value
        }
        // The course page starts this before the student taps "Programma":
        // the tap joins that search instead of starting a second one.
        if let running = pending[key] { return await running.value ?? nil }
        let task = Task { await findPick(teachingCode: teachingCode, surname: surname,
                                         degreeName: degreeName, yearCode: yearCode) }
        pending[key] = task
        let answer = await task.value
        pending[key] = nil
        // Not reached: asked again next time, not remembered as "none".
        guard let answer else { return await Self.storedPick(key)?.value }
        picks[key] = answer
        if let found = answer { await Self.storePick(found, key) }
        return answer
    }

    /// A week: schede change once a year, the picked row almost never.
    nonisolated static let storedLifetime: TimeInterval = 7 * 86400

    @concurrent
    private nonisolated static func storedPick(_ key: String) async -> DiskCache.Entry<SyllabusPicker.Pick>? {
        DiskCache.load(SyllabusPicker.Pick.self, as: pickFile(key))
    }

    @concurrent
    private nonisolated static func storePick(_ pick: SyllabusPicker.Pick, _ key: String) async {
        DiskCache.save(pick, as: pickFile(key))
    }

    private nonisolated static func pickFile(_ key: String) -> String {
        // By language too: the stored module and degree names are in it.
        "syllabus-pick-\(PoliMiLanguage.current.rawValue)-" + key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    }

    /// Starts finding a teaching's scheda, and its syllabus, without waiting.
    func prefetchSyllabus(teachingCode: String, surname: String?, degreeName: String?, yearCode: String?) {
        Task(priority: .utility) {
            let pick = await syllabusPick(teachingCode: teachingCode, surname: surname,
                                          degreeName: degreeName, yearCode: yearCode)
            if let id = pick?.module.syllabusID { _ = await syllabus(for: id) }
        }
    }

    @ObservationIgnored private var pending: [String: Task<SyllabusPicker.Pick??, Never>] = [:]

    /// Answers the catalogue actually gave — a scheda, or a real "none".
    @ObservationIgnored private var picks: [String: SyllabusPicker.Pick?] = [:]

    /// - Returns: nil when the catalogue could not be reached; otherwise its
    ///   answer, which may itself be no pick.
    private func findPick(teachingCode: String, surname: String?, degreeName: String?,
                          yearCode: String?) async -> SyllabusPicker.Pick?? {
        let form = [
            "evn_default": "Esegui Ricerca", "aa": yearCode ?? year.code, "k_cf": "-1", "sede": "ALL_SEDI",
            "tipoCorso": "ALL_TIPO_CORSO", "ac_ins": "0", "semestre": "ALL_SEMESTRI", "aree": "-1",
            "tipoInsegnamento": "ALL_TIPO_INSEGNAMENTO", "insegn_ricerca": teachingCode,
            "lang": PoliMiLanguage.current.rawValue, "jaf_currentWFID": "main",
        ]
        guard let html = await post("ricerche/RicercaPerInsegnamentoPublic.do", form: form,
                                    session: catalogue) else { return nil }
        var seen: Set<String> = []
        var rows: [ManifestoTeaching] = []
        // The student's degree course first, so it is never cut by the cap.
        let found = ManifestoParser.searchResults(html).filter { $0.code == teachingCode }
        for teaching in SyllabusPicker.ordered(found, degreeName: degreeName) {
            // One per degree course and plan: plans can bracket differently.
            if seen.insert("\(teaching.courseCode)-\(teaching.planCode ?? "")").inserted { rows.append(teaching) }
            if rows.count == Self.pickCandidates { break }
        }
        // The student's own degree course alone first: when it answers, the
        // other degree courses' pages are never read.
        let mine = rows.filter { DegreeCourseMatch.matches($0.degreeCourse, plan: degreeName) }
        if !mine.isEmpty, let early = SyllabusPicker.pick(await details(of: mine), surname: surname, degreeName: degreeName),
           early.matchesDegree {
            log.notice("manifesti: scheda for \(teachingCode, privacy: .public) from its own degree course: \(early.module.syllabusID ?? "none", privacy: .public)")
            return .some(early)
        }
        let details = await details(of: rows)
        // Rows found but no detail read: the pages did not load, which is
        // not an answer.
        if !rows.isEmpty && details.isEmpty { return nil }
        let pick = SyllabusPicker.pick(details, surname: surname, degreeName: degreeName)
        log.notice("manifesti: scheda for \(teachingCode, privacy: .public) from \(details.count, privacy: .public) degree courses: \(pick?.module.syllabusID ?? "none", privacy: .public)")
        return .some(pick)
    }

    /// Read together: one at a time, the course page waited for each. Already
    /// read pages come from the detail loader's cache.
    private func details(of rows: [ManifestoTeaching]) async -> [ManifestoDetail] {
        await withTaskGroup(of: (Int, ManifestoDetail?).self) { group in
            for (index, teaching) in rows.enumerated() {
                group.addTask { (index, await self.detail(for: teaching)) }
            }
            var found: [(Int, ManifestoDetail)] = []
            for await (index, detail) in group { if let detail { found.append((index, detail)) } }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Degree courses read to find a student's scheda. A common teaching is
    /// offered in dozens; the student's is usually among the first few, and
    /// every one costs a page.
    static let pickCandidates = 8

    // MARK: - Browsing by plan

    /// One step of the manifesto's cascade. Nil selection: the page as the
    /// service first shows it. Read without the cart's cookie, like every
    /// catalogue page.
    func cataloguePage(_ selection: CatalogueSelection?, language: PoliMiLanguage = .current) async -> CataloguePage? {
        var components = URLComponents()
        components.queryItems = selection?.queryItems(language: language) ?? [.init(name: "lang", value: language.rawValue)]
        guard let url = URL(string: "\(base.absoluteString)/ManifestoPublic.do?\(components.percentEncodedQuery ?? "")"),
              let html = await Self.page(url, session: catalogue) else { return nil }
        return CatalogueParser.page(html)
    }

    /// The page of a degree course, found in whichever school lists it: every
    /// school is read, across all campuses, and `choose` picks among each
    /// school's degree courses.
    func locateDegree(choosing choose: ([CatalogueOption]) -> CatalogueOption?) async -> CataloguePage? {
        guard let first = await cataloguePage(nil), let start = first.selection,
              let schools = first.level(.school)?.options else { return nil }
        for school in schools {
            let base = start.setting(.campus, to: "ALL_SEDI").setting(.school, to: school.value)
            guard let schoolPage = await cataloguePage(base) else { continue }
            if let match = choose(schoolPage.level(.degree)?.options ?? []) {
                return await cataloguePage(base.setting(.degree, to: match.value))
            }
        }
        return nil
    }

    func locateDegree(named degree: String, kind: String? = nil) async -> CataloguePage? {
        await locateDegree { DegreeCourseMatch.best($0, name: degree, kind: kind) }
    }

    /// The plans offering a teaching in a year, as manifesto selections: the
    /// search gives degree course and plan, each row's page names its school.
    func offeringPlans(teachingCode: String, yearCode: String) async -> [CatalogueSelection] {
        let form = [
            "evn_default": "Esegui Ricerca", "aa": yearCode, "k_cf": "-1", "sede": "ALL_SEDI",
            "tipoCorso": "ALL_TIPO_CORSO", "ac_ins": "0", "semestre": "ALL_SEMESTRI", "aree": "-1",
            "tipoInsegnamento": "ALL_TIPO_INSEGNAMENTO", "insegn_ricerca": teachingCode,
            "lang": PoliMiLanguage.current.rawValue, "jaf_currentWFID": "main",
        ]
        guard let html = await post("ricerche/RicercaPerInsegnamentoPublic.do", form: form, session: catalogue),
              let schools = await cataloguePage(nil)?.level(.school)?.options else { return [] }
        let rows = PlanCandidates.distinct(ManifestoParser.searchResults(html).filter { $0.code == teachingCode })
        // One teaching page per degree course names its school, read together.
        let firstOfDegree = PlanCandidates.distinct(rows.map { row in
            ManifestoTeaching(code: row.code, name: row.name, courseCode: row.courseCode, planCode: nil,
                              idItemOfferta: row.idItemOfferta, idRiga: row.idRiga, semester: row.semester, year: row.year,
                              credits: nil, school: nil, degreeCourse: nil)
        }).compactMap { degree in rows.first { $0.courseCode == degree.courseCode } }
        let schoolOfDegree = await withTaskGroup(of: (String, String?).self) { group in
            for row in firstOfDegree {
                group.addTask {
                    let name = await self.detail(for: row)?.context.first { $0.label.localizedCaseInsensitiveContains("Scuola")
                        || $0.label.localizedCaseInsensitiveContains("School") }?.value
                    return (row.courseCode, name.flatMap { PlanCandidates.school(named: $0, in: schools) })
                }
            }
            var found: [String: String] = [:]
            for await (degree, school) in group { if let school { found[degree] = school } }
            return found
        }
        return rows.compactMap { row in
            schoolOfDegree[row.courseCode].map {
                CatalogueSelection(year: yearCode, campus: "ALL_SEDI", school: $0, degree: row.courseCode, plan: row.planCode ?? "***")
            }
        }
    }

    /// The brackets a teaching is split into, with their lecturers; empty
    /// when it has one for everyone.
    func brackets(for teaching: ManifestoTeaching) async -> [BracketChoice] {
        let modules = await detail(for: teaching)?.modules ?? []
        let brackets = modules.compactMap(BracketChoice.init)
        return brackets.count > 1 ? brackets : []
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
        guard let html = await page("ManifestoPublic.do?\(detailQuery(teaching))") else { return nil }
        return PersonalTimetableParser.cartLink(in: html, code: teaching.code)
    }

    /// The sections a teaching asks the student to choose between, if any.
    ///
    /// Read on the cart's session, like the add link: the page offers the
    /// choice only once a name is set.
    func sections(for teaching: ManifestoTeaching)
        async -> (link: PersonalTimetableParser.SectionsLink, options: [PersonalTimetableParser.SectionOption])? {
        guard let html = await page("ManifestoPublic.do?\(detailQuery(teaching))"),
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

    private func post(_ path: String, form: [String: String], session: URLSession? = nil) async -> String? {
        let session = session ?? self.session
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
