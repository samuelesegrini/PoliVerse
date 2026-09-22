import Foundation

/// The five levels the manifesto is browsed by, in the order the Politecnico lays them
/// out.
///
/// Browsing down to a study plan is what makes a teaching's row unambiguous: every row
/// on a plan page is the student's degree course and plan, where searching the whole
/// catalogue for a name finds the same teaching in dozens of courses, each with its own
/// timetable.
///
/// The raw value is the form field's own name.
nonisolated enum CatalogueField: String, Sendable, CaseIterable {
    /// The academic year.
    case year = "aa"
    /// The campus.
    case campus = "sede"
    /// The school.
    case school = "k_cf"
    /// The degree course.
    case degree = "k_corso_la"
    /// The approved study plan within that course.
    case plan = "k_indir"
}

/// One choice at one level of the catalogue.
nonisolated struct CatalogueOption: Sendable, Hashable, Identifiable {
    /// ``value``.
    var id: String { value }
    /// What the form field is set to for this choice.
    let value: String
    /// The choice's text on the page.
    let label: String
    /// The elective group the row belongs to, for example “TABA”, when it is one.
    /// tells a bachelor's from a master's of the same name.
    let group: String?
}

/// One level of the catalogue, with its choices and the page's own.
nonisolated struct CatalogueLevel: Sendable, Hashable {
    /// Which level this is.
    let field: CatalogueField
    /// The choices the page offers here.
    let options: [CatalogueOption]
    /// What the page has chosen.
    ///
    /// Read back rather than assumed: the service settles every level below the one changed,
    /// so what it picked is not predictable.
    let selected: String?
}

/// A position in the catalogue: all five levels at once.
///
/// All five are always sent, because the service answers with an internal error when one
/// is missing.
nonisolated struct CatalogueSelection: Sendable, Hashable, Codable {
    /// The academic year.
    var year: String
    /// The campus.
    var campus: String
    /// The school.
    var school: String
    /// The degree course.
    var degree: String
    /// The study plan. `"***"` where the course offers no diversification.
    var plan: String

    /// One level's value.
    ///
    /// - Parameter field: The level to read.
    /// - Returns: Its value.
    subscript(field: CatalogueField) -> String {
        switch field {
        case .year: year
        case .campus: campus
        case .school: school
        case .degree: degree
        case .plan: plan
        }
    }

    /// A copy with one level changed.
    ///
    /// The levels below are sent as they were, and the service replaces whatever no longer
    /// fits.
    ///
    /// - Parameters:
    ///   - field: The level to change.
    ///   - value: Its new value.
    /// - Returns: The new selection.
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

    /// ``queryItems(language:)`` in the interface's current language.
    var queryItems: [URLQueryItem] { queryItems(language: .current) }

    /// The query items that ask the page for this position.
    ///
    /// Every year of course is requested, since the app groups by year itself.
    ///
    /// - Parameter language: Which language to ask the site for.
    /// - Returns: The query items.
    func queryItems(language: PoliMiLanguage) -> [URLQueryItem] {
        [.init(name: "evn_default", value: "Aggiorna")]
            + CatalogueField.allCases.map { .init(name: $0.rawValue, value: self[$0]) }
            // Every year of course: the app groups by year itself.
            + [.init(name: "ac_ins", value: "0"), .init(name: "lang", value: language.rawValue)]
    }
}

/// A teaching as a plan page lists it.
nonisolated struct PlanTeaching: Sendable, Hashable, Identifiable, Codable {
    /// The catalogue row's id.
    var id: String { teaching.id }
    /// The catalogue row itself.
    let teaching: ManifestoTeaching
    /// Which year of the course the row is listed under, from the heading above it.
    let yearOfCourse: String?
    /// The credits the row states.
    let credits: Double?
    /// The elective group the row belongs to, e.g. "TABA", when it is one.
    let group: String?
    /// Whether the teaching is offered in sections the student picks, rather than by
    /// alphabetical bracket.
    let hasSections: Bool

    /// Everything the timetable cart needs, straight from the row — so no detail page has to
    /// be fetched to add it.
    var cartLink: PersonalTimetableParser.CartLink {
        PersonalTimetableParser.CartLink(courseCode: teaching.courseCode, planCode: teaching.planCode ?? "",
                                         semester: teaching.semester ?? "", yearOfCourse: yearOfCourse ?? "0")
    }
}

/// One page of the catalogue: its levels, and the teachings it lists.
nonisolated struct CataloguePage: Sendable, Hashable {
    /// The levels the page offers, in ``CatalogueField`` order.
    let levels: [CatalogueLevel]
    /// The teachings listed, in page order. Empty above the study-plan level.
    let teachings: [PlanTeaching]

    /// One level of the page.
    ///
    /// - Parameter field: The level to read.
    /// - Returns: The level, or `nil` when the page does not offer it.
    func level(_ field: CatalogueField) -> CatalogueLevel? {
        levels.first { $0.field == field }
    }

    /// The position the page settled on, for asking it for another.
    ///
    /// A missing study-plan level becomes `"***"`. `nil` when any of the other four levels
    /// could not be read.
    var selection: CatalogueSelection? {
        guard let year = level(.year)?.selected, let campus = level(.campus)?.selected,
              let school = level(.school)?.selected, let degree = level(.degree)?.selected else { return nil }
        return CatalogueSelection(year: year, campus: campus, school: school, degree: degree,
                                  plan: level(.plan)?.selected ?? "***")
    }
}

/// Reads the catalogue's pages.
///
/// Regular expressions over template-generated markup, like ``HTMLScraper``, and not an
/// HTML parser.
nonisolated enum CatalogueParser {
    /// Reads a catalogue page.
    ///
    /// - Parameter html: The page.
    /// - Returns: The page, or `nil` for the service's error page — which is what it answers
    ///   for a campus with nothing offered in a year, among other things.
    static func page(_ html: String) -> CataloguePage? {
        let levels = CatalogueField.allCases.compactMap { level($0, in: html) }
        guard !levels.isEmpty else { return nil }
        return CataloguePage(levels: levels, teachings: teachings(html))
    }

    /// Reads one level off a catalogue page.
    ///
    /// A level with several choices is a `select`, whose `optgroup`s are kept. A level with
    /// one choice is written as a label and a hidden input in the same cell, sometimes
    /// separated by a line break, so the whole cell is read and everything before the input
    /// is the label — reading it any more narrowly leaves the level unread, and the page's
    /// selection then falls back to a plan the student is not in.
    ///
    /// The placeholder plan is dropped where real plans exist beside it, while the page's own
    /// choice is kept so a caller can move off it.
    ///
    /// - Parameters:
    ///   - field: The level to read.
    ///   - html: The page.
    /// - Returns: The level, or `nil` when the page does not carry it.
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

    /// Reads the teachings off a plan page.
    ///
    /// Headings split the page: a year heading sets the year, and an elective-group heading
    /// below it keeps that year, since a group belongs to the year it is listed under.
    /// Duplicate rows are dropped.
    ///
    /// - Parameter html: The page.
    /// - Returns: The teachings, in page order.
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

    /// Strips markup, collapses whitespace and trims.
    ///
    /// - Parameter text: The markup fragment.
    /// - Returns: The readable text.
    private static func clean(_ text: String) -> String {
        HTMLText.plain(text).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// An alphabetical bracket the student chose for one teaching, when it is not the one
/// their own name falls in — attending another lecturer's lessons, say.
nonisolated struct BracketChoice: Sendable, Hashable, Codable {
    /// Inclusive lower bound of the bracket.
    let from: String
    /// Exclusive upper bound.
    let to: String
    /// Who teaches this bracket, so the choice can be shown by lecturer.
    let teachers: [String]

    /// Creates a bracket choice.
    ///
    /// - Parameters:
    ///   - from: Inclusive lower bound.
    ///   - to: Exclusive upper bound.
    ///   - teachers: Who teaches it.
    init(from: String, to: String, teachers: [String]) {
        self.from = from
        self.to = to
        self.teachers = teachers
    }

    /// A choice for one of a teaching's modules.
    ///
    /// - Parameter module: The module.
    /// - Returns: `nil` for a module with no bracket.
    init?(_ module: ManifestoModule) {
        guard let from = module.scaglioneFrom, let to = module.scaglioneTo else { return nil }
        self.init(from: from, to: to, teachers: module.teachers.map(\.name))
    }

    /// A name that falls at the start of the bracket, for the cart to be named with.
    ///
    /// Surname and initial, as the service wants them: a bare `"CON"` is refused, and
    /// `"CON A"` is placed in the CON–FOT bracket.
    var cartName: String {
        "\(from.trimmingCharacters(in: .whitespaces)) A"
    }

    /// Whether a surname falls inside this bracket.
    ///
    /// - Parameter surname: The student's surname.
    /// - Returns: `true` when it falls inside, by
    ///   ``ManifestoModule/covers(surname:)``'s rules.
    func covers(surname: String) -> Bool {
        ManifestoModule(code: "", name: "", teachers: [], credits: nil, period: nil, language: nil,
                        scaglioneFrom: from, scaglioneTo: to, syllabusID: nil).covers(surname: surname)
    }

    /// The bracket as `"CON – FOT"`.
    var label: String {
        "\(from.trimmingCharacters(in: .whitespaces)) – \(to.trimmingCharacters(in: .whitespaces))"
    }
}

/// Splits a timetable's teachings into the carts the service needs.
///
/// Setting a name empties the cart, and the bracket of every teaching in it follows the
/// name set when the timetable is read. So each bracket other than the student's own is
/// its own cart, named by where that bracket starts, and the timetables are merged
/// afterwards.
nonisolated enum CartBatches {
    /// One cart: the name to set on it, and what to add.
    struct Batch: Sendable, Equatable {
        /// The name to set before adding, which decides the bracket.
        let cartName: String
        /// What to add under that name.
        var teachings: [ManifestoTeaching]
    }

    /// Groups teachings into carts by the name each needs.
    ///
    /// A chosen bracket the student's own surname already falls in needs no cart of its own.
    ///
    /// - Parameters:
    ///   - name: The student's full name, as the service wants it.
    ///   - surname: Their surname, taken apart from the name so a compound surname is
    ///     compared whole.
    ///   - teachings: What the timetable is being built from.
    ///   - brackets: The brackets the student chose, by teaching code.
    /// - Returns: The carts, the student's own name first, so a single-cart timetable is
    ///   built in one pass.
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
