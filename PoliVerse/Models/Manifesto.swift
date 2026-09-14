import Foundation

/// The Manifesti degli Studi — the university's course catalogue.
///
/// Public and unauthenticated, but HTML only: `onlineservices.polimi.it/manifesti`
/// is a Struts application with no API behind it. Everything here is parsed
/// from pages, which is why each type says which page it came from.
///
/// It answers questions the authenticated services cannot: what a course
/// actually covers, which books it uses, who teaches which alphabetical
/// bracket, and what a teaching looks like *before* you enrol in it.
nonisolated struct ManifestoTeaching: Identifiable, Sendable, Hashable {
    /// Composed, because no single field identifies a row: the same teaching
    /// code appears under several degree courses and study plans.
    var id: String { "\(courseCode)-\(code)-\(planCode ?? "")" }

    /// The teaching's own code, e.g. `086214`.
    let code: String
    let name: String
    /// `k_corso_la` — the degree course.
    let courseCode: String
    /// `k_indir` — the approved study plan.
    let planCode: String?
    let idItemOfferta: String?
    let idRiga: String?
    let semester: String?
    let year: String?
    let credits: Double?
    let school: String?
    let degreeCourse: String?
}

/// The language a teaching is delivered in, as the manifesto flags it.
///
/// Per module, not per teaching: the same teaching can be in English for one
/// degree course and in Italian for another, and a split teaching can run one
/// bracket in each. "Non definita" on the page is simply absent here.
nonisolated enum TeachingLanguage: String, Sendable, Hashable, Codable, CaseIterable {
    case italian, english

    /// The manifesto's own flag images: `flags/it.png`, `flags/en.png`.
    init?(flag: String) {
        switch flag.lowercased() {
        case "it": self = .italian
        case "en": self = .english
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .italian: String(localized: "Italiano")
        case .english: String(localized: "Inglese")
        }
    }
}

/// One module of a teaching, with the alphabetical bracket it serves.
///
/// Big first-year teachings are split by surname — the *scaglione* — and which
/// one a student belongs to decides their lecturer and their timetable. It is
/// the single most consequential field on the page and the one no other
/// Politecnico service exposes.
nonisolated struct ManifestoModule: Identifiable, Sendable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let teachers: [ManifestoTeacher]
    let credits: Double?
    let period: String?
    let language: TeachingLanguage?
    /// Inclusive lower bound of the surname bracket, e.g. `"A"`.
    let scaglioneFrom: String?
    /// Exclusive upper bound, e.g. `"ZZZZ"`.
    let scaglioneTo: String?
    /// `c_classe` for the syllabus, where the page offers one.
    let syllabusID: String?

    /// Whether a surname falls in this module's bracket.
    ///
    /// The bounds are "from inclusive, to exclusive", as the page itself
    /// labels them: a bracket `CAS`–`FER` takes Casati but not Ferrari.
    /// Compared case- and accent-insensitively, because a student types their
    /// own name the way they write it, not the way the registry stores it.
    func covers(surname: String) -> Bool {
        guard let from = scaglioneFrom, let to = scaglioneTo else { return true }
        let key = ManifestoModule.sortKey(surname)
        return key >= ManifestoModule.sortKey(from) && key < ManifestoModule.sortKey(to)
    }

    static func sortKey(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: Locale(identifier: "it_IT"))
            .trimmingCharacters(in: .whitespaces)
    }
}

nonisolated struct ManifestoTeacher: Identifiable, Sendable, Hashable {
    /// `k_doc`, the catalogue's own id — the name-to-id lookup that was
    /// missing when teacher search was first built from course lists.
    var id: String { kDoc ?? name.lowercased() }
    let name: String
    let kDoc: String?
}

/// A subject area with its credits, from the SSD table.
nonisolated struct ManifestoSSD: Identifiable, Sendable, Hashable {
    var id: String { code }
    /// e.g. `MAT/05`.
    let code: String
    let name: String
    let credits: Double?
    /// Attività formativa — `A` di base, `B` caratterizzante, and so on.
    let kind: String?
}

/// Everything the detail page says about one teaching.
nonisolated struct ManifestoDetail: Sendable, Hashable {
    let code: String
    let name: String
    /// Context: which degree, plan and year this row belongs to.
    let context: [(label: String, value: String)]
    /// The scheda: type, credits, period, short programme.
    let facts: [(label: String, value: String)]
    /// The short programme, pulled out of ``facts`` because it is prose and
    /// wants a different presentation from a key/value row.
    let summary: String?
    let ssd: [ManifestoSSD]
    let modules: [ManifestoModule]
    /// Every language the teaching is offered in on this page, in order.
    /// Read from the rows themselves, so it is there even when the module
    /// table has no code column to parse modules from.
    let languages: [TeachingLanguage]

    /// "Corso di Studi" from the context card: which degree course this row is.
    var degreeCourse: String? {
        context.first { $0.label.localizedCaseInsensitiveContains("Corso di Studi") }?.value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.code == rhs.code && lhs.name == rhs.name
            && lhs.modules == rhs.modules && lhs.ssd == rhs.ssd && lhs.languages == rhs.languages
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
        hasher.combine(name)
    }
}

/// One degree course's bracket for a teaching, from the syllabus summary.
nonisolated struct SyllabusBracket: Sendable, Hashable {
    let degreeCourse: String
    let from: String?
    let to: String?
}

/// A book in the syllabus bibliography.
nonisolated struct SyllabusBook: Sendable, Hashable, Identifiable {
    var id: String { "\(title)-\(authors ?? "")" }
    let authors: String?
    let title: String
    /// Publisher, year, ISBN, as the page writes them.
    let details: String?
    let url: URL?
    /// "Risorsa bibliografica obbligatoria" rather than "facoltativa".
    let isRequired: Bool
}

/// Hours of one kind of teaching: lectures, labs, projects.
nonisolated struct TeachingForm: Sendable, Hashable {
    let name: String
    let minutes: Int
}

/// What an Italian or English-taught course offers in English.
nonisolated enum EnglishSupport: String, Sendable, Hashable, CaseIterable {
    case slides, books, exam, tutoring

    var label: String {
        switch self {
        case .slides: String(localized: "Slide e materiale in inglese")
        case .books: String(localized: "Libri di testo in inglese")
        case .exam: String(localized: "Esame sostenibile in inglese")
        case .tutoring: String(localized: "Supporto didattico in inglese")
        }
    }
}

/// The syllabus — `SchedaPublic.do?c_classe=…`, a different service again.
///
/// This is where the books are. It is public, and reachable directly: the
/// catalogue links it through `aunicalogin`, but that only redirects to the
/// same page with two throwaway tokens, so the app skips the round trip.
nonisolated struct Syllabus: Sendable, Hashable {
    /// The prose sections, title to body, in the order the page presents them —
    /// obiettivi, risultati di apprendimento attesi, argomenti trattati,
    /// prerequisiti, modalità di valutazione. Everything the page states as
    /// data is read into the fields below instead.
    var sections: [(title: String, body: String)]

    /// Titolare first, then co-titolari.
    var teachers: [ManifestoTeacher] = []
    var credits: Double?
    /// "Monodisciplinare", "Integrato", …
    var teachingType: String?
    /// The bracket this teaching serves in each degree course that offers it.
    var brackets: [SyllabusBracket] = []
    /// How the exam works, as the page lists it: "Prova scritta obbligatoria,
    /// senza prove in itinere", "Prova orale condizionata".
    var assessment: [String] = []
    /// The teacher's own description of the exam, when there is one.
    var assessmentNotes: String?
    var books: [SyllabusBook] = []
    var software: String?
    /// Only the forms with hours, in page order.
    var teachingForms: [TeachingForm] = []
    var assistedMinutes: Int?
    var selfStudyMinutes: Int?
    var language: TeachingLanguage?
    /// What is available in English. Listed only when it applies.
    var englishSupport: [EnglishSupport] = []

    var bibliography: String? {
        sections.first { $0.title.localizedCaseInsensitiveContains("bibliograf") }?.body
            ?? (books.isEmpty ? nil : books.map(\.title).joined(separator: "; "))
    }

    var objectives: String? {
        sections.first { $0.title.localizedCaseInsensitiveContains("obiettiv") }?.body
    }

    var topics: String? {
        sections.first { $0.title.localizedCaseInsensitiveContains("argomenti") }?.body
    }

    /// Nothing read at all — the service's search page, typically, which it
    /// returns for an unknown class id.
    var isEmpty: Bool {
        sections.isEmpty && assessment.isEmpty && books.isEmpty && teachers.isEmpty
            && teachingForms.isEmpty && software == nil && language == nil && brackets.isEmpty
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sections.map(\.title) == rhs.sections.map(\.title) && lhs.sections.map(\.body) == rhs.sections.map(\.body)
            && lhs.assessment == rhs.assessment && lhs.books == rhs.books && lhs.teachers == rhs.teachers
            && lhs.language == rhs.language && lhs.englishSupport == rhs.englishSupport
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sections.count)
    }
}

/// An academic year as the catalogue names it: `2026` means 2026/2027.
nonisolated struct AcademicYear: Identifiable, Sendable, Hashable {
    var id: String { code }
    let code: String
    var label: String {
        guard let start = Int(code) else { return code }
        return "\(start)/\(start + 1)"
    }

    /// The years the catalogue offers, newest first. The service exposes six.
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
