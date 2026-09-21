import Foundation

/// One made-up but complete Ingegneria Informatica degree, and the single
/// place every other sample reads from.
///
/// The demo used to be written out area by area: the libretto listed Basi di
/// Dati at 8 CFU, the course page at 10, the gradebook carried a hand-typed
/// 27.4 average that matched neither, and the same exam was sat 640 days ago
/// in one file and 190 in another. A student exploring the app was shown
/// three different careers depending on which tab they opened.
///
/// So nothing below is written twice. ``SampleDegree/teachings`` is the plan —
/// twenty-two teachings, 180 CFU, three years — and the libretto, the
/// gradebook, the sittings, the courses and the week's timetable are all
/// *derived* from it. The average is computed by the same ``StudyPlan`` the
/// real career uses, so Carriera and Simulazione media cannot disagree: there
/// is only one number.
///
/// The plan is also chosen to exercise the app rather than to look tidy. It
/// carries a mark with honours and a mark of 22, an *idoneità* with no number
/// at all, two teachings failed once before they were passed, a mark still
/// inside its refusal window, a sitting the student is enrolled in the day
/// after tomorrow, an enrolment window about to close, a window not yet open,
/// and one closed without enrolling — every state ``CareerState`` can paint,
/// and every card ``CareerNowCard`` can show.
nonisolated enum SampleDegree {
    /// A sitting already taken. `mark` is nil when it was not passed — a
    /// failed attempt is part of a real career and the app draws it.
    struct Attempt: Sendable {
        /// How long ago, in months. Chosen to land in the Politecnico's real
        /// sessions: January–February, June–July, September.
        let monthsAgo: Double
        let mark: Int?
        var lode = false

        var passed: Bool { (mark ?? 0) >= 18 }
    }

    /// What a teaching is examined by. Drives the words on the sitting and
    /// the shape of ``ExamFormatSection``.
    enum Assessment: String, Sendable {
        case written = "Scritto"
        case oral = "Orale"
        case writtenAndOral = "Scritto e orale"
        case writtenAndProject = "Scritto e progetto"
        case project = "Progetto"
        case qualifying = "Idoneità"
    }

    /// One line of the study plan.
    struct Teaching: Identifiable, Sendable {
        let code: String
        let name: String
        let teacher: String
        let cfu: Int
        /// 1, 2 or 3 — the year of the course it belongs to.
        let year: Int
        /// 1 or 2.
        let semester: Int
        let assessment: Assessment
        /// Oldest first. Empty for a teaching never sat.
        var attempts: [Attempt] = []
        /// Passed without a mark: the English requirement, the final project.
        var isQualifying = false
        /// Lecture topics, in the order they are taught. WeBeep's sample
        /// material is built from these, so a course's files are about the
        /// course rather than the same four Assembly slides everywhere.
        var topics: [String] = []
        /// Work handed in on WeBeep: the name and how many days from now it
        /// is due. Negative is already closed.
        var assignments: [(name: String, dueInDays: Double)] = []

        var id: String { code }

        /// The sitting that passed it, if one did.
        var passingAttempt: Attempt? { attempts.last { $0.passed } }
        var isPassed: Bool { passingAttempt != nil || (isQualifying && !attempts.isEmpty) }
        /// The mark that counts. Nil for an *idoneità*, which has none — and
        /// which must therefore stay out of every average.
        var mark: Int? { passingAttempt?.mark }
        var hasLode: Bool { passingAttempt?.lode ?? false }
    }

    // MARK: - The plan

    /// Twenty-two teachings, 180 CFU. The student is starting the third year
    /// with the second still not quite closed — the ordinary case, and the
    /// one with the most to show.
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

    static func teaching(_ code: String) -> Teaching {
        teachings.first { $0.code == code }!
    }

    /// The teachings whose lectures are running now: third year, first
    /// semester. What the week's timetable and the course pages are made of.
    static var currentTeachings: [Teaching] {
        teachings.filter { $0.year == 3 && $0.semester == 1 }
    }

    /// Everything still to sit, in plan order — what the sittings list and
    /// the September session are drawn from.
    static var pending: [Teaching] {
        teachings.filter { !$0.isPassed && !$0.isQualifying }
    }

    static var plannedCFU: Int { teachings.reduce(0) { $0 + $1.cfu } }

    // MARK: - Dates

    /// `monthsAgo` as a real date, at an hour an exam would plausibly start.
    ///
    /// Whole months back from today keeps every sitting inside a real session
    /// — the plan's offsets were picked for that — without pinning the demo
    /// to a calendar year that goes stale the moment it ships.
    static func date(monthsAgo: Double, hour: Int = 9, now: Date = .now) -> Date {
        let calendar = PoliMiDate.romeCalendar
        let seconds = -monthsAgo * 30.44 * 86_400
        let day = now.addingTimeInterval(seconds)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    /// The academic year a teaching was taught in, written the way the
    /// Politecnico writes it. Derived from today, so the demo never claims to
    /// be three years out of date.
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
