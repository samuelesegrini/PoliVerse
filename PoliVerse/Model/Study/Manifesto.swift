import Foundation

/// One row of the Manifesti degli Studi — the university's course catalogue.
///
/// The catalogue is public and unauthenticated but HTML only: a Struts application with
/// no API behind it, so every type in this file is parsed from a page and says which.
///
/// It answers questions the authenticated services cannot: what a course covers, which
/// books it uses, who teaches which alphabetical bracket, and what a teaching looks like
/// before a student enrols in it.
nonisolated struct ManifestoTeaching: Identifiable, Sendable, Hashable, Codable {
    /// The degree course, the teaching and the plan together.
    ///
    /// Composed because no single field identifies a row: one teaching code appears under
    /// several degree courses and study plans.
    var id: String { "\(courseCode)-\(code)-\(planCode ?? "")" }

    /// The teaching's own six-digit code.
    let code: String
    /// The teaching's name.
    let name: String
    /// `k_corso_la` — the degree course this row belongs to.
    let courseCode: String
    /// `k_indir` — the approved study plan within that course.
    let planCode: String?
    /// The offering's identifier, which the sections picker and the cart need.
    let idItemOfferta: String?
    /// The catalogue row's identifier.
    let idRiga: String?
    /// The semester the teaching runs in.
    let semester: String?
    /// The academic year of the offering. Absent on some search results, which is what
    /// ``detailQuery(defaultYear:)`` takes a default for.
    let year: String?
    /// The teaching's credits, where the row states them.
    let credits: Double?
    /// The school offering the degree course.
    let school: String?
    /// The degree course's name, as the catalogue spells it.
    let degreeCourse: String?
    /// The query string naming this teaching's page on the Manifesti site.
    ///
    /// On the value rather than on a model because both build it — the catalogue to read the
    /// scheda, the cart to find the add link on the same page — and it is derivation from
    /// these fields and nothing else.
    ///
    /// - Parameter defaultYear: Used where the row carries no ``year`` of its own.
    /// - Returns: The percent-encoded query.
    func detailQuery(defaultYear: String) -> String {
        var items = [
            URLQueryItem(name: "EVN_DETTAGLIO_RIGA_MANIFESTO", value: "evento"),
            URLQueryItem(name: "k_corso_la", value: courseCode),
            URLQueryItem(name: "codDescr", value: code),
            URLQueryItem(name: "aa", value: year ?? defaultYear),
            URLQueryItem(name: "lang", value: PoliMiLanguage.current.rawValue),
            URLQueryItem(name: "jaf_currentWFID", value: "main"),
        ]
        if let planCode { items.append(.init(name: "k_indir", value: planCode)) }
        if let idItemOfferta { items.append(.init(name: "idItemOfferta", value: idItemOfferta)) }
        if let idRiga { items.append(.init(name: "idRiga", value: idRiga)) }
        if let semester { items.append(.init(name: "semestre", value: semester)) }

        var components = URLComponents()
        components.queryItems = items
        return components.percentEncodedQuery ?? ""
    }

}

/// The language a teaching is delivered in, as the manifesto flags it.
///
/// Per module rather than per teaching: the same teaching can be in English for one
/// degree course and in Italian for another, and a split teaching can run one bracket in
/// each. “Non definita” on the page is simply absent here.
nonisolated enum TeachingLanguage: String, Sendable, Hashable, Codable, CaseIterable {
    /// The two languages the manifesto flags.
    case italian, english

    /// Reads the language off the manifesto's own flag image name.
    ///
    /// - Parameter flag: `it` or `en`, in any case.
    /// - Returns: `nil` for anything else, including an undefined language.
    init?(flag: String) {
        switch flag.lowercased() {
        case "it": self = .italian
        case "en": self = .english
        default: return nil
        }
    }

    /// The language's name on screen.
    var label: String {
        switch self {
        case .italian: String(localized: "Italiano")
        case .english: String(localized: "Inglese")
        }
    }

    /// A whole phrase saying the teaching is in this language.
    ///
    /// A phrase rather than the name in a template, because languages are capitalised
    /// differently mid-sentence in Italian and English.
    var taughtIn: String {
        switch self {
        case .italian: String(localized: "Insegnamento in italiano")
        case .english: String(localized: "Insegnamento in inglese")
        }
    }
}

/// One module of a teaching, with the alphabetical bracket it serves.
///
/// Large first-year teachings are split by surname — the *scaglione* — and which one a
/// student belongs to decides their lecturer and their timetable. It is the most
/// consequential field on the page and the one no other Politecnico service exposes.
nonisolated struct ManifestoModule: Identifiable, Sendable, Hashable, Codable {
    /// ``code``.
    var id: String { code }
    /// The module's own code.
    let code: String
    /// The module's name.
    let name: String
    /// Who teaches it.
    let teachers: [ManifestoTeacher]
    /// The module's credits.
    let credits: Double?
    /// When it runs, as the page writes it.
    let period: String?
    /// Which language it is delivered in, where the page flags one.
    let language: TeachingLanguage?
    /// Inclusive lower bound of the surname bracket, for example `"A"`.
    let scaglioneFrom: String?
    /// Exclusive upper bound, for example `"ZZZZ"`.
    let scaglioneTo: String?
    /// `c_classe`, which opens the syllabus, where the page offers one.
    let syllabusID: String?

    /// Whether a surname falls in this module's bracket.
    ///
    /// The bounds are inclusive below and exclusive above, as the page labels them, so a
    /// bracket CAS–FER takes Casati but not Ferrari. Compared case- and accent-insensitively,
    /// because a student writes their name the way they write it rather than the way the
    /// registry stores it.
    ///
    /// - Parameter surname: The student's surname.
    /// - Returns: `true` when the surname falls inside, and always `true` for a module with
    ///   no bracket.
    func covers(surname: String) -> Bool {
        guard let from = scaglioneFrom, let to = scaglioneTo else { return true }
        let key = ManifestoModule.sortKey(surname)
        return key >= ManifestoModule.sortKey(from) && key < ManifestoModule.sortKey(to)
    }

    /// A name reduced to its comparable form for bracket comparison: folded to ignore case
    /// and accents, and trimmed.
    ///
    /// - Parameter value: The name or bound as written.
    /// - Returns: The comparable form.
    static func sortKey(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: Locale(identifier: "it_IT"))
            .trimmingCharacters(in: .whitespaces)
    }
}

/// A member of teaching staff as the catalogue names them.
nonisolated struct ManifestoTeacher: Identifiable, Sendable, Hashable, Codable {
    /// ``kDoc`` where the catalogue gives one, and the lower-cased name otherwise.
    var id: String { kDoc ?? name.lowercased() }
    /// The lecturer's name.
    let name: String
    /// `k_doc`, the catalogue's own identifier for the lecturer.
    let kDoc: String?
}

/// A subject area with its credits, from the manifesto's SSD table.
nonisolated struct ManifestoSSD: Identifiable, Sendable, Hashable {
    /// ``code``.
    var id: String { code }
    /// The subject area's code, for example `MAT/05`.
    let code: String
    /// The subject area's name.
    let name: String
    /// The credits attributed to this area.
    let credits: Double?
    /// The *attività formativa* — `A` for di base, `B` for caratterizzante, and so on.
    let kind: String?
}

/// Everything a teaching's detail page in the manifesto says.
nonisolated struct ManifestoDetail: Sendable, Hashable {
    /// The teaching's code.
    let code: String
    /// The teaching's name.
    let name: String
    /// Which degree course, plan and year this row belongs to, as label and value pairs.
    let context: [(label: String, value: String)]
    /// The scheda's own rows: type, credits, period and so on.
    let facts: [(label: String, value: String)]
    /// The short programme, taken out of ``facts`` because it is prose and wants a different
    /// presentation from a key-and-value row.
    let summary: String?
    /// The subject areas and their credits.
    let ssd: [ManifestoSSD]
    /// The teaching's modules, in the page's order.
    let modules: [ManifestoModule]
    /// Every language the teaching is offered in on this page, in order.
    ///
    /// Read from the rows themselves, so it is present even when the module table has no code
    /// column to parse modules from.
    let languages: [TeachingLanguage]

    /// Which degree course this row is, read from the context card's “Corso di Studi”. `nil`
    /// when the page carries no such row.
    var degreeCourse: String? {
        context.first { $0.label.localizedCaseInsensitiveContains("Corso di Studi") }?.value
    }

    /// Compares the fields that identify a page, since ``context`` and ``facts`` hold tuples
    /// and cannot be synthesised.
    ///
    /// - Parameters:
    ///   - lhs: The first detail.
    ///   - rhs: The second.
    /// - Returns: `true` when they describe the same teaching with the same modules, subject
    ///   areas and languages.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.code == rhs.code && lhs.name == rhs.name
            && lhs.modules == rhs.modules && lhs.ssd == rhs.ssd && lhs.languages == rhs.languages
    }

    /// Hashes the teaching's code and name.
    ///
    /// - Parameter hasher: The hasher to feed.
    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        hasher.combine(name)
    }
}

/// One degree course's alphabetical bracket for a teaching, from the syllabus summary.
nonisolated struct SyllabusBracket: Sendable, Hashable, Codable {
    /// The degree course this bracket belongs to.
    let degreeCourse: String
    /// Inclusive lower bound of the surname bracket.
    let from: String?
    /// Exclusive upper bound.
    let to: String?
}

/// A book in the syllabus bibliography.
nonisolated struct SyllabusBook: Sendable, Hashable, Identifiable, Codable {
    /// The title and authors together.
    var id: String { "\(title)-\(authors ?? "")" }
    /// The authors, as the page writes them.
    let authors: String?
    /// The book's title.
    let title: String
    /// Publisher, year and ISBN, as the page writes them.
    let details: String?
    /// Where the book can be found, where the page links one.
    let url: URL?
    /// Whether the page calls it a required bibliographic resource rather than an optional
    /// one.
    let isRequired: Bool
}

/// Hours of one kind of teaching: lectures, laboratories, projects.
nonisolated struct TeachingForm: Sendable, Hashable, Codable {
    /// The form of teaching, as the page names it.
    let name: String
    /// How many minutes of it the syllabus allots.
    let minutes: Int
}

/// What a course offers in English, whichever language it is taught in.
nonisolated enum EnglishSupport: String, Sendable, Hashable, CaseIterable, Codable {
    /// Slides and material, textbooks, sitting the exam, and teaching support.
    case slides, books, exam, tutoring

    /// The offering's description on screen.
    var label: String {
        switch self {
        case .slides: String(localized: "Slide e materiale in inglese")
        case .books: String(localized: "Libri di testo in inglese")
        case .exam: String(localized: "Esame sostenibile in inglese")
        case .tutoring: String(localized: "Supporto didattico in inglese")
        }
    }
}

/// A teaching's syllabus, from `SchedaPublic.do?c_classe=…`.
///
/// This is where the books are. The page is public and reachable directly: the catalogue
/// links it through the sign-in service, but that only redirects to the same page with
/// two throwaway tokens, so the app skips the round trip.
///
/// Everything the page states as data is read into the fields below; the prose is left in
/// ``sections``.
nonisolated struct Syllabus: Sendable, Hashable {
    /// The prose sections, title to body, in the page's own order — objectives, expected
    /// learning outcomes, topics, prerequisites, assessment.
    var sections: [(title: String, body: String)]

    /// The titolare first, then any co-titolari.
    var teachers: [ManifestoTeacher] = []
    /// The teaching's credits.
    var credits: Double?
    /// “Monodisciplinare”, “Integrato”, and so on.
    var teachingType: String?
    /// The bracket this teaching serves in each degree course that offers it.
    var brackets: [SyllabusBracket] = []
    /// How the exam works, as the page lists it — which ``PartialExams/policy(assessment:notes:)``
    /// reads for partial exams.
    var assessment: [String] = []
    /// The lecturer's own description of the exam, where there is one.
    var assessmentNotes: String?
    /// The bibliography.
    var books: [SyllabusBook] = []
    /// The software the course expects, where the page names any.
    var software: String?
    /// The forms of teaching that have hours, in page order.
    var teachingForms: [TeachingForm] = []
    /// Minutes of assisted teaching the syllabus allots.
    var assistedMinutes: Int?
    /// Minutes of independent study the syllabus allots.
    var selfStudyMinutes: Int?
    /// The language the teaching is delivered in.
    var language: TeachingLanguage?
    /// What is available in English. Listed only where it applies.
    var englishSupport: [EnglishSupport] = []

    /// The bibliography as prose: the page's own section where there is one, and otherwise
    /// the books' titles joined together. `nil` when there is neither.
    var bibliography: String? {
        sections.first { $0.title.localizedCaseInsensitiveContains("bibliograf") }?.body
            ?? (books.isEmpty ? nil : books.map(\.title).joined(separator: "; "))
    }

    /// The objectives section, or `nil` when the page has none.
    var objectives: String? {
        sections.first { $0.title.localizedCaseInsensitiveContains("obiettiv") }?.body
    }

    /// The topics section, or `nil` when the page has none.
    var topics: String? {
        sections.first { $0.title.localizedCaseInsensitiveContains("argomenti") }?.body
    }

    /// Whether nothing was read at all — typically the service's search page, which it
    /// returns for an unknown class id.
    var isEmpty: Bool {
        sections.isEmpty && assessment.isEmpty && books.isEmpty && teachers.isEmpty
            && teachingForms.isEmpty && software == nil && language == nil && brackets.isEmpty
    }

    /// Compares the fields that identify a syllabus, since ``sections`` holds tuples and
    /// cannot be synthesised.
    ///
    /// - Parameters:
    ///   - lhs: The first syllabus.
    ///   - rhs: The second.
    /// - Returns: `true` when the prose, assessment, books, lecturers, language and English
    ///   support all agree.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sections.map(\.title) == rhs.sections.map(\.title) && lhs.sections.map(\.body) == rhs.sections.map(\.body)
            && lhs.assessment == rhs.assessment && lhs.books == rhs.books && lhs.teachers == rhs.teachers
            && lhs.language == rhs.language && lhs.englishSupport == rhs.englishSupport
    }

    /// Hashes the number of prose sections.
    ///
    /// - Parameter hasher: The hasher to feed.
    func hash(into hasher: inout Hasher) {
        hasher.combine(sections.count)
    }
}

/// Persistence, so a scheda opens instantly on the next launch.
///
/// ``sections`` is written as pairs, since tuples have no `Codable`.
extension Syllabus: Codable {
    /// One prose section, in a shape that can be encoded.
    private struct Section: Codable { let title: String; let body: String }

    /// One key per stored property.
    private enum CodingKeys: String, CodingKey {
        case sections, teachers, credits, teachingType, brackets, assessment, assessmentNotes, books, software,
             teachingForms, assistedMinutes, selfStudyMinutes, language, englishSupport
    }

    /// Decodes a stored syllabus.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: A decoding error when a required key is missing.
    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sections: try c.decode([Section].self, forKey: .sections).map { (title: $0.title, body: $0.body) })
        teachers = try c.decode([ManifestoTeacher].self, forKey: .teachers)
        credits = try c.decodeIfPresent(Double.self, forKey: .credits)
        teachingType = try c.decodeIfPresent(String.self, forKey: .teachingType)
        brackets = try c.decode([SyllabusBracket].self, forKey: .brackets)
        assessment = try c.decode([String].self, forKey: .assessment)
        assessmentNotes = try c.decodeIfPresent(String.self, forKey: .assessmentNotes)
        books = try c.decode([SyllabusBook].self, forKey: .books)
        software = try c.decodeIfPresent(String.self, forKey: .software)
        teachingForms = try c.decode([TeachingForm].self, forKey: .teachingForms)
        assistedMinutes = try c.decodeIfPresent(Int.self, forKey: .assistedMinutes)
        selfStudyMinutes = try c.decodeIfPresent(Int.self, forKey: .selfStudyMinutes)
        language = try c.decodeIfPresent(TeachingLanguage.self, forKey: .language)
        englishSupport = try c.decode([EnglishSupport].self, forKey: .englishSupport)
    }

    /// Encodes the syllabus for storage.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder raises.
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sections.map { Section(title: $0.title, body: $0.body) }, forKey: .sections)
        try c.encode(teachers, forKey: .teachers)
        try c.encodeIfPresent(credits, forKey: .credits)
        try c.encodeIfPresent(teachingType, forKey: .teachingType)
        try c.encode(brackets, forKey: .brackets)
        try c.encode(assessment, forKey: .assessment)
        try c.encodeIfPresent(assessmentNotes, forKey: .assessmentNotes)
        try c.encode(books, forKey: .books)
        try c.encodeIfPresent(software, forKey: .software)
        try c.encode(teachingForms, forKey: .teachingForms)
        try c.encodeIfPresent(assistedMinutes, forKey: .assistedMinutes)
        try c.encodeIfPresent(selfStudyMinutes, forKey: .selfStudyMinutes)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encode(englishSupport, forKey: .englishSupport)
    }
}

/// An academic year as the catalogue names it: `2026` means 2026/2027.
nonisolated struct AcademicYear: Identifiable, Sendable, Hashable {
    /// ``code``.
    var id: String { code }
    /// The year the academic year begins in, as the catalogue keys it.
    let code: String
    /// The year as `"2026/2027"`, or the code itself when it is not a number.
    var label: String {
        guard let start = Int(code) else { return code }
        return "\(start)/\(start + 1)"
    }

    /// The years the catalogue offers, newest first.
    ///
    /// The service exposes six. A new manifesto appears in spring for the year that starts in
    /// the autumn, so the latest is this calendar year once March has passed and the previous
    /// one before.
    ///
    /// - Parameter now: The date the list is derived from.
    /// - Returns: Six years, newest first.
    static func recent(from now: Date = .now) -> [AcademicYear] {
        let calendar = PoliMiDate.romeCalendar
        let year = calendar.component(.year, from: now)
        // The new manifesto appears in spring for the year that starts in
        // autumn, so the current one is this calendar year once we are past
        // it, and the previous one before.
        let latest = calendar.component(.month, from: now) >= 3 ? year : year - 1
        return (0..<6).map { AcademicYear(code: String(latest - $0)) }
    }
}
