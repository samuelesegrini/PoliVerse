import Foundation

/// One complete fictional Ingegneria Informatica degree, and the single source every
/// other sample reads from.
///
/// ``teachings`` is the plan — twenty-two teachings, 180 credits, three years — and
/// the libretto, the grade book, the sittings, the courses, the week's timetable and
/// the WeBeep material are all derived from it. The average is computed by the same
/// ``StudyPlan`` the real career uses, so no two screens can disagree about the same
/// student.
///
/// The plan is chosen to exercise the app rather than to look tidy. It carries a mark
/// with honours and a mark of 22, an *idoneità* with no mark at all, two teachings
/// failed once before being passed, a mark still inside its refusal window, a sitting
/// the student is enrolled in, an enrolment window about to close, one not yet open,
/// and one closed without enrolling.
nonisolated enum SampleDegree {
    /// A sitting already taken.
    struct Attempt: Sendable {
        /// How long ago the sitting was, in months. Chosen to land in the Politecnico's real
        /// sessions: January–February, June–July and September.
        let monthsAgo: Double
        /// The mark awarded, or `nil` for a sitting that was not passed or that carried no
        /// mark.
        let mark: Int?
        /// Whether the mark carried honours.
        var lode = false

        /// Whether the attempt passed.
        var passed: Bool { (mark ?? 0) >= 18 }
    }

    /// What a teaching is examined by. Its raw value is the sitting's
    /// ``ExamSession/kind``, and it shapes ``ExamFormatSection``.
    enum Assessment: String, Sendable {
        /// A written exam.
        case written = "Scritto"
        /// An oral exam.
        case oral = "Orale"
        /// A written exam followed by an oral.
        case writtenAndOral = "Scritto e orale"
        /// A written exam alongside a project.
        case writtenAndProject = "Scritto e progetto"
        /// A project alone.
        case project = "Progetto"
        /// Passed without a mark.
        case qualifying = "Idoneità"
    }

    /// One line of the study plan.
    struct Teaching: Identifiable, Sendable {
        /// The six-digit teaching code, which is also its identity.
        let code: String
        /// The teaching's name.
        let name: String
        /// The lecturer.
        let teacher: String
        /// The teaching's credits.
        let cfu: Int
        /// The year of the course it belongs to: 1, 2 or 3.
        let year: Int
        /// The semester it runs in: 1 or 2.
        let semester: Int
        /// What it is examined by.
        let assessment: Assessment
        /// Sittings taken, oldest first. Empty for a teaching never sat.
        var attempts: [Attempt] = []
        /// Whether it is passed without a mark — the English requirement, the final project —
        /// and so stays out of every average.
        var isQualifying = false
        /// Lecture topics, in teaching order. The sample WeBeep material is built from these,
        /// so a course's files are about that course.
        var topics: [String] = []
        /// Work handed in on WeBeep, with how many days from now it is due. A negative value
        /// is a deadline already closed.
        var assignments: [(name: String, dueInDays: Double)] = []

        /// ``code``.
        var id: String { code }

        /// The latest attempt that passed, or `nil` when none did.
        var passingAttempt: Attempt? { attempts.last { $0.passed } }
        /// Whether the teaching is passed. A qualifying teaching counts as passed once it has
        /// been attempted at all, since it carries no mark.
        var isPassed: Bool { passingAttempt != nil || (isQualifying && !attempts.isEmpty) }
        /// The mark that counts, or `nil` for an *idoneità* — which must stay out of every
        /// average.
        var mark: Int? { passingAttempt?.mark }
        /// Whether the mark that counts carried honours.
        var hasLode: Bool { passingAttempt?.lode ?? false }
    }

    // MARK: - The plan

    /// The whole plan: twenty-two teachings, 180 credits, three years.
    ///
    /// The student is starting the third year with the second not quite closed.
    static let teachings: [Teaching] = [
        // ---- Year one: done, and long enough ago to give the chart a run-up.
        Teaching(code: "086088", name: "Analisi Matematica 1", teacher: "Gianmaria Verzini",
                 cfu: 10, year: 1, semester: 1, assessment: .writtenAndOral,
                 attempts: [Attempt(monthsAgo: 32, mark: 30, lode: true)]),
        Teaching(code: "052470", name: "Geometria e Algebra Lineare", teacher: "Federico Bambozzi",
                 cfu: 10, year: 1, semester: 1, assessment: .written,
                 // Failed in January, passed in June: the app shows both.
                 attempts: [Attempt(monthsAgo: 32, mark: 15), Attempt(monthsAgo: 27, mark: 27)]),
        Teaching(code: "097785", name: "Fondamenti di Informatica", teacher: "Luca Breveglieri",
                 cfu: 12, year: 1, semester: 1, assessment: .writtenAndProject,
                 attempts: [Attempt(monthsAgo: 32, mark: 26)]),
        Teaching(code: "083801", name: "Fisica Sperimentale A", teacher: "Paola Taroni",
                 cfu: 8, year: 1, semester: 2, assessment: .writtenAndOral,
                 attempts: [Attempt(monthsAgo: 27, mark: 25)]),
        Teaching(code: "083802", name: "Chimica Generale", teacher: "Chiara Castiglioni",
                 cfu: 6, year: 1, semester: 2, assessment: .written,
                 attempts: [Attempt(monthsAgo: 27, mark: 27)]),
        Teaching(code: "086944", name: "Reti Logiche", teacher: "Fabrizio Ferrandi",
                 cfu: 10, year: 1, semester: 2, assessment: .writtenAndProject,
                 attempts: [Attempt(monthsAgo: 24, mark: 28)]),
        // No mark at all: it must not move the average, and the libretto has
        // to say something other than a number.
        Teaching(code: "088786", name: "Prova di Lingua Inglese B2", teacher: "Language Centre",
                 cfu: 3, year: 1, semester: 2, assessment: .qualifying,
                 attempts: [Attempt(monthsAgo: 26, mark: nil)], isQualifying: true),

        // ---- Year two: nearly closed, and where the average dips.
        Teaching(code: "083803", name: "Analisi Matematica 2", teacher: "Filippo Gazzola",
                 cfu: 8, year: 2, semester: 1, assessment: .written,
                 attempts: [Attempt(monthsAgo: 20, mark: 24)]),
        Teaching(code: "085923", name: "Architetture dei Calcolatori e Sistemi Operativi",
                 teacher: "Marco Santambrogio",
                 cfu: 10, year: 2, semester: 1, assessment: .writtenAndOral,
                 attempts: [Attempt(monthsAgo: 20, mark: 26)]),
        Teaching(code: "097671", name: "Probabilità e Statistica", teacher: "Ilenia Epifani",
                 cfu: 8, year: 2, semester: 1, assessment: .written,
                 attempts: [Attempt(monthsAgo: 20, mark: 16), Attempt(monthsAgo: 15, mark: 22)]),
        Teaching(code: "084392", name: "Informatica Teorica", teacher: "Dino Mandrioli",
                 cfu: 8, year: 2, semester: 2, assessment: .written,
                 attempts: [Attempt(monthsAgo: 15, mark: 30)]),
        Teaching(code: "095951", name: "Algoritmi e Principi dell'Informatica", teacher: "Matteo Pradella",
                 cfu: 10, year: 2, semester: 2, assessment: .writtenAndOral,
                 attempts: [Attempt(monthsAgo: 12, mark: 29)]),
        Teaching(code: "086655", name: "Elettrotecnica", teacher: "Luca Di Rienzo",
                 cfu: 6, year: 2, semester: 2, assessment: .oral,
                 attempts: [Attempt(monthsAgo: 15, mark: 25)]),
        // Sat three days ago: the mark is published and still refusable, which
        // is the whole reason Adesso's refusal card exists.
        Teaching(code: "095946", name: "Basi di Dati", teacher: "Stefano Ceri",
                 cfu: 10, year: 2, semester: 2, assessment: .writtenAndOral,
                 attempts: [Attempt(monthsAgo: 3, mark: 17), Attempt(monthsAgo: 0.1, mark: 26)],
                 topics: ["Il modello relazionale",
                          "Algebra relazionale",
                          "SQL: interrogazioni",
                          "Progettazione concettuale ed Entity-Relationship",
                          "Normalizzazione",
                          "Transazioni e concorrenza"]),
        // Still open: one with a window closing, one already enrolled.
        Teaching(code: "089156", name: "Economia e Organizzazione Aziendale", teacher: "Cinzia Colapinto",
                 cfu: 6, year: 2, semester: 2, assessment: .written,
                 topics: ["Il bilancio d'esercizio",
                          "Analisi dei costi",
                          "Valutazione degli investimenti"]),
        Teaching(code: "091250", name: "Ricerca Operativa", teacher: "Edoardo Amaldi",
                 cfu: 10, year: 2, semester: 2, assessment: .written,
                 topics: ["Programmazione lineare",
                          "Il metodo del simplesso",
                          "Dualità",
                          "Programmazione lineare intera",
                          "Flussi su reti"]),

        // ---- Year three: the semester now starting. These are the timetable.
        Teaching(code: "095948", name: "Ingegneria del Software", teacher: "Carlo Ghezzi",
                 cfu: 12, year: 3, semester: 1, assessment: .project,
                 topics: ["Introduzione al corso e al progetto",
                          "Requisiti: elicitazione e specifica",
                          "Diagrammi di sequenza e di stato",
                          "Architetture a microservizi",
                          "Verifica: test di unità e di integrazione",
                          "Alloy e verifica formale"],
                 assignments: [("Documento di analisi dei requisiti (RASD)", 9),
                               ("Design document", 37),
                               ("Consegna del codice e dei test", 71)]),
        Teaching(code: "086657", name: "Reti di Calcolatori", teacher: "Antonio Capone",
                 cfu: 10, year: 3, semester: 1, assessment: .writtenAndProject,
                 topics: ["Il modello a livelli",
                          "Livello applicativo: HTTP e DNS",
                          "Livello di trasporto: TCP e UDP",
                          "Controllo di congestione",
                          "Instradamento IP"],
                 assignments: [("Laboratorio 1 — cattura e analisi del traffico", 2),
                               ("Laboratorio 2 — socket TCP", 23)]),
        Teaching(code: "095857", name: "Automatica", teacher: "Sergio Matteo Savaresi",
                 cfu: 10, year: 3, semester: 1, assessment: .writtenAndOral,
                 topics: ["Sistemi dinamici e modelli di stato",
                          "Trasformata di Laplace",
                          "Stabilità e criterio di Routh",
                          "Diagrammi di Bode",
                          "Progetto del regolatore"],
                 assignments: [("Esercitazione Matlab — risposta al gradino", -4)]),
        Teaching(code: "089160", name: "Sicurezza Informatica", teacher: "Stefano Zanero",
                 cfu: 5, year: 3, semester: 2, assessment: .oral),
        Teaching(code: "097683", name: "Tecnologie Informatiche per il Web", teacher: "Piero Fraternali",
                 cfu: 5, year: 3, semester: 2, assessment: .project),
        Teaching(code: "090000", name: "Prova Finale", teacher: "Relatore da assegnare",
                 cfu: 3, year: 3, semester: 2, assessment: .qualifying, isQualifying: true),
    ]

    // MARK: - Reading the plan

    /// The teaching with a given code.
    ///
    /// - Parameter code: A code that must appear in ``teachings``.
    /// - Returns: The teaching.
    static func teaching(_ code: String) -> Teaching {
        teachings.first { $0.code == code }!
    }

    /// The teachings whose lectures are running now — third year, first semester — which
    /// the week's timetable and the course pages are built from.
    static var currentTeachings: [Teaching] {
        teachings.filter { $0.year == 3 && $0.semester == 1 }
    }

    /// Everything still to sit, in plan order, which the sittings list is drawn from.
    /// Qualifying teachings are excluded.
    static var pending: [Teaching] {
        teachings.filter { !$0.isPassed && !$0.isQualifying }
    }

    /// The plan's total credits.
    static var plannedCFU: Int { teachings.reduce(0) { $0 + $1.cfu } }

    // MARK: - Dates

    /// An ``Attempt/monthsAgo`` offset as a real date, at an hour an exam would plausibly
    /// start.
    ///
    /// Measured back from the current date, so the sample never pins itself to a calendar
    /// year that goes stale.
    ///
    /// - Parameters:
    ///   - monthsAgo: How far back, in months of 30.44 days.
    ///   - hour: The hour of day, in Rome.
    ///   - now: The date to measure back from.
    /// - Returns: The resolved date.
    static func date(monthsAgo: Double, hour: Int = 9, now: Date = .now) -> Date {
        let calendar = PoliMiDate.romeCalendar
        let seconds = -monthsAgo * 30.44 * 86_400
        let day = now.addingTimeInterval(seconds)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    /// The academic year a teaching was taught in, as `"2025/26"`.
    ///
    /// Derived from the current date on the assumption that the student is in their third
    /// year, so the sample never claims to be years out of date. The year turns in
    /// September.
    ///
    /// - Parameters:
    ///   - teaching: The teaching to place.
    ///   - now: The date to derive from.
    /// - Returns: The year label.
    static func academicYear(for teaching: Teaching, now: Date = .now) -> String {
        let calendar = PoliMiDate.romeCalendar
        // The academic year turns over in the autumn, not in January.
        let month = calendar.component(.month, from: now)
        let thisYear = calendar.component(.year, from: now) - (month >= 9 ? 0 : 1)
        // The student is in their third year: year 1 was two years back.
        let start = thisYear - (3 - teaching.year)
        return "\(start)/\(String(format: "%02d", (start + 1) % 100))"
    }
}
