import Foundation

/// The manifesto browsed the way the Politecnico lays it out: academic year,
/// campus, school, degree course, approved study plan — then that plan's
/// teachings, by year of course.
///
/// Searching the whole catalogue for a teaching name found the same teaching
/// in dozens of degree courses, each with its own timetable, and left the
/// student to guess which row was theirs. The plan page answers that by
/// construction: every row on it is the student's degree course and plan.
nonisolated enum CatalogueField: String, Sendable, CaseIterable {
    case year = "aa"
    case campus = "sede"
    case school = "k_cf"
    case degree = "k_corso_la"
    case plan = "k_indir"
}

nonisolated struct CatalogueOption: Sendable, Hashable, Identifiable {
    var id: String { value }
    let value: String
    let label: String
    /// The `optgroup` it sits in, e.g. "Laurea Magistrale - ord. 96/23".
    let group: String?
}

nonisolated struct CatalogueLevel: Sendable, Hashable {
    let field: CatalogueField
    let options: [CatalogueOption]
    /// What the page has chosen: the service settles every level below the
    /// one changed, so this is read back rather than assumed.
    let selected: String?
}

/// The five values the page is asked for. All five are always sent: the
/// service answers "Errore interno" when one is missing.
nonisolated struct CatalogueSelection: Sendable, Hashable, Codable {
    var year: String
    var campus: String
    var school: String
    var degree: String
    var plan: String

    subscript(field: CatalogueField) -> String {
        switch field {
        case .year: year
        case .campus: campus
        case .school: school
        case .degree: degree
        case .plan: plan
        }
    }

    /// Only the level changed: the ones below are sent as they were and the
    /// service replaces whatever no longer fits.
    func setting(_ field: CatalogueField, to value: String) -> CatalogueSelection {
        var copy = self
        switch field {
        case .year: copy.year = value
        case .campus: copy.campus = value
        case .school: copy.school = value
        case .degree: copy.degree = value
        case .plan: copy.plan = value
        }
        return copy
    }

    var queryItems: [URLQueryItem] { queryItems(language: .current) }

    func queryItems(language: PoliMiLanguage) -> [URLQueryItem] {
        [.init(name: "evn_default", value: "Aggiorna")]
            + CatalogueField.allCases.map { .init(name: $0.rawValue, value: self[$0]) }
            // Every year of course: the app groups by year itself.
            + [.init(name: "ac_ins", value: "0"), .init(name: "lang", value: language.rawValue)]
    }
}

/// A teaching as the plan page lists it.
nonisolated struct PlanTeaching: Sendable, Hashable, Identifiable, Codable {
    var id: String { teaching.id }
    let teaching: ManifestoTeaching
    /// "1", "2", … from the heading above the row.
    let yearOfCourse: String?
    let credits: Double?
    /// The elective group the row belongs to, e.g. "TABA", when it is one.
    let group: String?
    /// Offered in sections the student picks, rather than by bracket.
    let hasSections: Bool

    /// Everything the cart needs, straight from the row: no detail page.
    var cartLink: PersonalTimetableParser.CartLink {
        PersonalTimetableParser.CartLink(courseCode: teaching.courseCode, planCode: teaching.planCode ?? "",
                                         semester: teaching.semester ?? "", yearOfCourse: yearOfCourse ?? "0")
    }
}

nonisolated struct CataloguePage: Sendable, Hashable {
    let levels: [CatalogueLevel]
    let teachings: [PlanTeaching]

    func level(_ field: CatalogueField) -> CatalogueLevel? {
        levels.first { $0.field == field }
    }

    var selection: CatalogueSelection? {
        guard let year = level(.year)?.selected, let campus = level(.campus)?.selected,
              let school = level(.school)?.selected, let degree = level(.degree)?.selected else { return nil }
        return CatalogueSelection(year: year, campus: campus, school: school, degree: degree,
                                  plan: level(.plan)?.selected ?? "***")
    }
}

nonisolated enum CatalogueParser {
    /// Nil for the service's error page — what it answers for a campus with
    /// nothing offered in a year, among other things.
    static func page(_ html: String) -> CataloguePage? {
        let levels = CatalogueField.allCases.compactMap { level($0, in: html) }
        guard !levels.isEmpty else { return nil }
        return CataloguePage(levels: levels, teachings: teachings(html))
    }

    static func level(_ field: CatalogueField, in html: String) -> CatalogueLevel? {
        let name = NSRegularExpression.escapedPattern(for: field.rawValue)
        if let select = HTMLScraper.firstMatch(#"<select[^>]*name="\#(name)"[^>]*>(.*?)</select>"#, in: html, group: 1) {
            var options: [CatalogueOption] = []
            var selected: String?
            // Optgroups in order, then the options of each; loose options
            // (no group) come through the same pattern with an empty label.
            let parts = HTMLScraper.matches(#"(?:<optgroup[^>]*label="([^"]*)"[^>]*>)?((?:\s*<option[^>]*>[^<]*(?:</option>)?)+)"#, in: select)
            for part in parts {
                let group = part.count > 1 && !part[0].contains("<option") ? clean(part[0]) : nil
                let body = part.last ?? ""
                for option in HTMLScraper.matches(#"<option([^>]*)>([^<]*)"#, in: body) where option.count == 2 {
                    guard let value = HTMLScraper.firstMatch(#"value="([^"]*)""#, in: option[0], group: 1) else { continue }
                    options.append(CatalogueOption(value: value, label: clean(option[1]), group: group.flatMap { $0.isEmpty ? nil : $0 }))
                    if option[0].localizedCaseInsensitiveContains("selected") { selected = value }
                }
            }
            guard !options.isEmpty else { return nil }
            // "*** - Non diversificato" lists nothing where real plans exist
            // beside it (the Architecture school offers it as a choice).
            // The page's own choice is kept, so a caller can move off it.
            if field == .plan, options.contains(where: { $0.value != "***" }) {
                options.removeAll { $0.value == "***" }
            }
            return CatalogueLevel(field: field, options: options, selected: selected ?? options.first?.value)
        }
        // One choice only: the page writes its label and a hidden input in the
        // same cell — but not always next to each other. The plan's cell puts
        // a `<br/>` between them, which a pattern demanding the input right
        // after the text missed: the level then went unread, and the page's
        // selection fell back to "***", so the app followed a plan the
        // student is not in and its teachings were not theirs. So the cell is
        // read whole and everything before the input is the label.
        let cell = #"<td[^>]*>((?:(?!</td>).)*?)<input([^>]*\bname="\#(name)"[^>]*)>"#
        guard let match = HTMLScraper.matches(cell, in: html).first, match.count == 2,
              let value = HTMLScraper.firstMatch(#"value="([^"]*)""#, in: match[1], group: 1)
        else { return nil }
        let option = CatalogueOption(value: value, label: clean(match[0]), group: nil)
        return CatalogueLevel(field: field, options: [option], selected: option.value)
    }

    private static func teachings(_ html: String) -> [PlanTeaching] {
        var found: [PlanTeaching] = []
        var seen: Set<String> = []
        // Headings split the page: "3° Anno" sets the year, and a group
        // heading below it ("Insegnamenti del Gruppo TABA") keeps that year —
        // an elective group belongs to the year it is listed under.
        var year: String?
        var group: String?
        for piece in html.components(separatedBy: "TitleInfoCard\">") {
            if let heading = HTMLScraper.firstMatch(#"^\s*([0-9])\s*<sup>"#, in: piece, group: 1) {
                year = heading
                group = nil
            } else if let name = HTMLScraper.firstMatch(#"^\s*(?:Insegnamenti del Gruppo|Courses of Group|Group)\s*([^<]*)"#, in: piece, group: 1) {
                group = clean(name)
            }
            for row in HTMLScraper.rows(in: piece) {
                guard let linkCell = row.first(where: { $0.localizedCaseInsensitiveContains("EVN_DETTAGLIO_RIGA_MANIFESTO") }),
                      let href = HTMLScraper.href(in: linkCell),
                      let code = HTMLScraper.queryValue("codDescr", in: href),
                      let course = HTMLScraper.queryValue("k_corso_la", in: href) else { continue }
                let cells = row.map(HTMLScraper.text)
                let name = row.compactMap { cell -> String? in
                    guard cell.localizedCaseInsensitiveContains("EVN_DETTAGLIO_RIGA_MANIFESTO") else { return nil }
                    let text = HTMLScraper.text(cell); return text.isEmpty ? nil : text
                }.first ?? code
                let teaching = ManifestoTeaching(
                    code: code, name: name, courseCode: course,
                    planCode: HTMLScraper.queryValue("k_indir", in: href),
                    idItemOfferta: HTMLScraper.queryValue("idItemOfferta", in: href),
                    idRiga: HTMLScraper.queryValue("idRiga", in: href),
                    semester: HTMLScraper.queryValue("semestre", in: href),
                    year: HTMLScraper.queryValue("aa", in: href),
                    credits: nil, school: HTMLScraper.queryValue("k_cf", in: href), degreeCourse: nil)
                guard seen.insert(teaching.id).inserted else { continue }
                found.append(PlanTeaching(
                    teaching: teaching,
                    yearOfCourse: HTMLScraper.queryValue("anno_corso", in: href) ?? year,
                    credits: cells.compactMap(ManifestoParser.credits(from:)).last,
                    group: HTMLScraper.queryValue("idGruppo", in: href) == nil ? nil : group,
                    hasSections: row.contains { $0.contains("con_sezioni") }))
            }
        }
        return found
    }

    private static func clean(_ text: String) -> String {
        HTMLText.plain(text).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A bracket the student chose for one teaching, when it is not the one their
/// name falls in — attending another lecturer's lessons, say.
nonisolated struct BracketChoice: Sendable, Hashable, Codable {
    let from: String
    let to: String
    let teachers: [String]

    init(from: String, to: String, teachers: [String]) {
        self.from = from
        self.to = to
        self.teachers = teachers
    }

    init?(_ module: ManifestoModule) {
        guard let from = module.scaglioneFrom, let to = module.scaglioneTo else { return nil }
        self.init(from: from, to: to, teachers: module.teachers.map(\.name))
    }

    /// A name that falls at the start of the bracket. Surname and name, as
    /// the service wants them: a bare "CON" is refused with "Orario non
    /// ancora definito", "CON A" is placed in CON–FOT.
    var cartName: String {
        "\(from.trimmingCharacters(in: .whitespaces)) A"
    }

    func covers(surname: String) -> Bool {
        ManifestoModule(code: "", name: "", teachers: [], credits: nil, period: nil, language: nil,
                        scaglioneFrom: from, scaglioneTo: to, syllabusID: nil).covers(surname: surname)
    }

    var label: String {
        "\(from.trimmingCharacters(in: .whitespaces)) – \(to.trimmingCharacters(in: .whitespaces))"
    }
}

/// The carts one timetable needs.
///
/// Setting a name on the service empties its cart, and the bracket of every
/// teaching in it follows the name set when the timetable is read. So each
/// bracket other than the student's own is its own cart, named by where that
/// bracket starts, and the timetables are merged afterwards. Checked live on
/// 2026-09-14: "Conti Mario" and "CON A" both read Analisi 1 with the CON–FOT
/// lecturer; back to "Rossi Mario", the cart is empty.
nonisolated enum CartBatches {
    struct Batch: Sendable, Equatable {
        let cartName: String
        var teachings: [ManifestoTeaching]
    }

    /// - Parameter surname: asked for apart from `name`, so a compound surname
    ///   is compared whole; a chosen bracket it already falls in needs no cart
    ///   of its own.
    static func batches(name: String, surname: String, teachings: [ManifestoTeaching],
                        brackets: [String: BracketChoice]) -> [Batch] {
        var batches: [Batch] = []
        for teaching in teachings {
            let cartName = brackets[teaching.code].flatMap { bracket in
                bracket.covers(surname: surname) ? nil : bracket.cartName
            } ?? name
            if let index = batches.firstIndex(where: { $0.cartName == cartName }) {
                batches[index].teachings.append(teaching)
            } else {
                batches.append(Batch(cartName: cartName, teachings: [teaching]))
            }
        }
        // The student's own name first, so a single-cart timetable is built
        // exactly as before.
        return batches.filter { $0.cartName == name } + batches.filter { $0.cartName != name }
    }
}
