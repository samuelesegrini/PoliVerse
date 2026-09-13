import Foundation

/// Something that changed about the student's exams since the app last looked.
///
/// The Politecnico sends no change feed: the exam services answer "what is
/// true now", and the app already showed that. What it did not do was
/// *notice* — a room published overnight looked exactly like a room that had
/// always been there. An update is that difference, recorded once, with where
/// it came from.
///
/// See `docs/academic-intelligence-layer.md` §6 for the full event model; this
/// is the slice fed only by official data. Most facts are read straight off a
/// field; the few that are inferred say so (``confidenceNote``).
nonisolated struct ExamUpdate: Identifiable, Sendable, Equatable, Codable {
    nonisolated enum Kind: String, Sendable, Codable, CaseIterable {
        case discovered, enrolmentOpened, enrolled, unenrolled
        case roomPublished, roomChanged, dateChanged, withdrawn
        case gradePublished, refusalOpened, correctionsAvailable, gradeRecorded
        /// WeBeep, tagged from the file's name — see ``DocumentClassifier``.
        case resultsPosted, solutionsPosted, examNoticePosted, materialAdded

        var symbol: String {
            switch self {
            case .discovered: "calendar.badge.plus"
            case .enrolmentOpened: "door.left.hand.open"
            case .enrolled: "checkmark.circle"
            case .unenrolled: "xmark.circle"
            case .roomPublished, .roomChanged: "mappin.and.ellipse"
            case .dateChanged: "calendar.badge.exclamationmark"
            case .withdrawn: "calendar.badge.minus"
            case .gradePublished: "rosette"
            case .refusalOpened: "arrow.uturn.backward.circle"
            case .correctionsAvailable: "doc.text.magnifyingglass"
            case .gradeRecorded: "checkmark.seal"
            case .resultsPosted: "tablecells"
            case .solutionsPosted: "doc.text.magnifyingglass"
            case .examNoticePosted: "megaphone"
            case .materialAdded: "folder.badge.plus"
            }
        }
    }

    nonisolated enum Source: String, Sendable, Codable {
        /// `iae/v1/insegn` — the registration service.
        case exams
        /// `elencoinsegnamenti` — the libretto.
        case libretto
        /// `core_course_get_contents` — a WeBeep course page.
        case webeep

        var label: String {
            switch self {
            case .exams: String(localized: "Servizi Online · iscrizione esami")
            case .libretto: String(localized: "Servizi Online · libretto")
            case .webeep: String(localized: "WeBeep · pagina del corso")
            }
        }
    }

    /// How sure the app is that this happened.
    nonisolated enum Confidence: String, Sendable, Codable {
        /// Read straight off a field that changed.
        case exact
        /// Inferred from an absence or a join by code — right almost always,
        /// but not a field saying so.
        case high
        /// A name that fits more than one reading. Never pushed on its own.
        case probable
    }

    /// What the student is told, decided once when the update is recorded.
    nonisolated enum Delivery: String, Sendable, Codable {
        /// Shown in the app, never pushed.
        case inApp
        /// Pushed now, within the daily allowance.
        case push
        /// Pushed now, never rationed — Alta in §11.2 but not imminent.
        case priority
        /// Pushed now, allowed through Focus.
        case urgent
        /// Folded into the evening summary.
        case digest
        /// Held back by quiet hours; summarised in the morning.
        case morning

        var isImmediate: Bool { self == .push || self == .priority || self == .urgent }
    }

    /// Stable for the same change: seeing it twice in quick succession
    /// produces the same id, so the log can refuse the second copy.
    let id: String
    let kind: Kind
    let examID: Int?
    let courseCode: String
    let courseName: String
    let detectedAt: Date
    let source: Source
    let confidence: Confidence
    /// Which field said so, e.g. `iae:/v1/insegn c_appello=123 xaula`.
    let evidence: String
    let oldValue: String?
    let newValue: String?
    /// Whether the student was signed up when this was seen — what makes a
    /// room change urgent rather than trivia.
    let wasEnrolled: Bool
    let examDate: Date?
    var delivery: Delivery = .inApp

    init(kind: Kind, examID: Int?, courseCode: String, courseName: String,
         detectedAt: Date, source: Source, confidence: Confidence = .exact,
         evidence: String, oldValue: String? = nil, newValue: String? = nil,
         identity: String? = nil,
         wasEnrolled: Bool, examDate: Date?, delivery: Delivery = .inApp) {
        // `identity` stands in for the value when the value alone would call
        // two different changes the same — a file re-uploaded under its name.
        self.id = [kind.rawValue, examID.map(String.init) ?? courseCode, identity ?? newValue ?? "-"]
            .joined(separator: "|")
        self.kind = kind
        self.examID = examID
        self.courseCode = courseCode
        self.courseName = courseName
        self.detectedAt = detectedAt
        self.source = source
        self.confidence = confidence
        self.evidence = evidence
        self.oldValue = oldValue
        self.newValue = newValue
        self.wasEnrolled = wasEnrolled
        self.examDate = examDate
        self.delivery = delivery
    }

    var title: String {
        switch kind {
        case .discovered: String(localized: "Nuovo appello")
        case .enrolmentOpened: String(localized: "Iscrizioni aperte")
        case .enrolled: String(localized: "Iscrizione registrata")
        case .unenrolled: String(localized: "Iscrizione annullata")
        case .roomPublished: String(localized: "Aula pubblicata")
        case .roomChanged: String(localized: "Aula cambiata")
        case .dateChanged: String(localized: "Appello spostato")
        case .withdrawn: String(localized: "Appello non più disponibile")
        case .gradePublished: String(localized: "Esito pubblicato")
        case .refusalOpened: String(localized: "Puoi rifiutare il voto")
        case .correctionsAvailable: String(localized: "Correzione disponibile")
        case .gradeRecorded: String(localized: "Voto registrato nel libretto")
        // Worded as what was seen, not as what it probably means: a file
        // named "Esiti" is not the student's grade.
        case .resultsPosted: String(localized: "Pubblicato un file di esiti")
        case .solutionsPosted: String(localized: "Pubblicate le soluzioni")
        case .examNoticePosted: String(localized: "Nuovo avviso d'esame")
        case .materialAdded: String(localized: "Nuovo materiale")
        }
    }

    /// One line of detail beyond the course name, where there is one.
    var detail: String? {
        switch kind {
        case .roomPublished: newValue.map { String(localized: "Aula \($0)") }
        case .roomChanged:
            if let oldValue, let newValue { String(localized: "Da \(oldValue) a \(newValue)") } else { nil }
        case .gradePublished, .gradeRecorded: newValue.map { String(localized: "Voto: \($0)") }
        case .resultsPosted, .solutionsPosted, .examNoticePosted:
            // A file put up again over an old one, or under a new name.
            isReplacement ? newValue.map { String(localized: "\($0) (nuova versione)") } : newValue
        case .materialAdded: newValue.flatMap(Int.init).map { String(localized: "\($0) nuovi file") }
        default: nil
        }
    }

    var sourceLabel: String { source.label }

    /// A WeBeep file that replaced an earlier one of the same kind.
    var isReplacement: Bool { source == .webeep && oldValue != nil }

    /// Said out loud when the fact is inferred rather than read, so it never
    /// looks as certain as a field.
    var confidenceNote: String? {
        switch (confidence, kind) {
        case (.exact, _): nil
        case (.high, .withdrawn): String(localized: "Dedotto: assente in due letture consecutive")
        case (.high, .resultsPosted), (.high, .solutionsPosted), (.high, .examNoticePosted),
             (.high, .materialAdded): String(localized: "Dedotto dal nome del file")
        case (.probable, _): String(localized: "Dal nome del file, ambiguo")
        case (.high, _): String(localized: "Dedotto: collegato per insegnamento")
        }
    }
}

/// What the detector remembers between looks.
nonisolated struct ExamWatchState: Sendable, Equatable, Codable {
    /// The last good snapshot of sittings, by `c_appello`. Nil until one has
    /// been seen, which is what makes the first look a silent baseline.
    var exams: [Int: ExamFacts]?
    /// Future sittings missing from the latest answer, waiting for a second
    /// miss before they count as withdrawn.
    var missing: Set<Int> = []
    /// Libretto rows by id, `true` when passed.
    var libretto: [String: Bool]?
}

/// The parts of a sitting whose change is worth noticing, normalised.
nonisolated struct ExamFacts: Sendable, Equatable, Codable {
    let id: Int
    let courseCode: String
    let courseName: String
    let date: Date?
    let room: String?
    let enrolmentOpen: Bool
    /// Graded counts as enrolled: a mark implies a registration.
    let enrolled: Bool
    let graded: Bool
    let gradeText: String?
    let refusable: Bool
    let hasCorrections: Bool

    init(_ session: ExamSession) {
        id = session.id
        courseCode = session.courseCode
        courseName = session.courseName
        date = session.date
        room = session.room?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        enrolmentOpen = session.status == .open
        graded = session.grade != nil
        enrolled = session.status == .enrolled || graded
        gradeText = session.grade?.display
        refusable = session.grade?.refusable ?? false
        hasCorrections = session.hasCorrections
    }
}

/// Compares two looks at the exam services and says what changed.
///
/// Pure, and tested as such. The rules that matter most are about when not
/// to compare: the first look, a failed request, and the empty answer the
/// services give between sessions all leave the state alone and report
/// nothing, because a false "appello annullato" is worse than a late true one.
nonisolated enum ExamChangeDetector {
    struct Result: Sendable {
        let updates: [ExamUpdate]
        let state: ExamWatchState
    }

    /// - Parameters:
    ///   - sessions: nil when the request failed.
    ///   - libretto: nil when the request failed.
    static func detect(
        previous: ExamWatchState?,
        sessions: [ExamSession]?,
        libretto: [LibrettoExam]?,
        now: Date
    ) -> Result {
        var state = previous ?? ExamWatchState()
        var updates: [ExamUpdate] = []

        if let sessions, !sessions.isEmpty {
            let current = Dictionary(sessions.map { ($0.id, ExamFacts($0)) },
                                     uniquingKeysWith: { first, _ in first })
            if let old = state.exams {
                updates += compare(old: old, new: current, missing: &state.missing, now: now)
                // Kept while waiting for the second miss, so the withdrawal
                // still has a name and a date to report.
                var next = current
                for id in state.missing { next[id] = old[id] }
                state.exams = next
            } else {
                state.exams = current
            }
        }

        if let libretto, !libretto.isEmpty {
            let current = Dictionary(libretto.map { ($0.id, $0.isPassed) },
                                     uniquingKeysWith: { first, _ in first })
            if let old = state.libretto {
                for exam in libretto where exam.isPassed && old[exam.id] == false {
                    updates.append(ExamUpdate(
                        kind: .gradeRecorded, examID: nil,
                        courseCode: exam.id, courseName: exam.name,
                        detectedAt: now, source: .libretto,
                        // Joined by the row's id, not by a sitting.
                        confidence: .high,
                        evidence: "libretto:elencoinsegnamenti \(exam.id) sostenuti",
                        newValue: exam.grade.map { exam.hasLode ? "\($0)L" : String($0) },
                        wasEnrolled: true, examDate: exam.date))
                }
            }
            state.libretto = current
        }

        return Result(updates: updates, state: state)
    }

    private static func compare(
        old: [Int: ExamFacts], new: [Int: ExamFacts], missing: inout Set<Int>, now: Date
    ) -> [ExamUpdate] {
        var updates: [ExamUpdate] = []

        for (id, facts) in new.sorted(by: { $0.key < $1.key }) {
            missing.remove(id)
            func update(_ kind: ExamUpdate.Kind, field: String,
                        from oldValue: String? = nil, to newValue: String? = nil) {
                updates.append(ExamUpdate(
                    kind: kind, examID: id, courseCode: facts.courseCode,
                    courseName: facts.courseName, detectedAt: now, source: .exams,
                    evidence: "iae:/v1/insegn c_appello=\(id) \(field)",
                    oldValue: oldValue, newValue: newValue,
                    wasEnrolled: facts.enrolled, examDate: facts.date))
            }

            guard let before = old[id] else {
                // A sitting that is already over is history, not news.
                if (facts.date ?? .distantFuture) >= now { update(.discovered, field: "c_appello") }
                continue
            }

            if !before.enrolmentOpen, !before.enrolled, facts.enrolmentOpen {
                update(.enrolmentOpened, field: "iscrizioniAperte")
            }
            if !before.enrolled, facts.enrolled, !facts.graded {
                update(.enrolled, field: "iscrizioneAttiva")
            } else if before.enrolled, !facts.enrolled {
                update(.unenrolled, field: "iscrizioneAttiva")
            }
            if before.room == nil, let room = facts.room {
                update(.roomPublished, field: "xaula", to: room)
            } else if let was = before.room, let room = facts.room, was != room {
                update(.roomChanged, field: "xaula", from: was, to: room)
            }
            if let was = before.date, let date = facts.date, was != date {
                update(.dateChanged, field: "d_app ora_ok",
                       from: was.ISO8601Format(), to: date.ISO8601Format())
            }
            if !before.graded, facts.graded {
                update(.gradePublished, field: "hasEsito", to: facts.gradeText)
            }
            if !before.refusable, facts.refusable {
                update(.refusalOpened, field: "rifiutabile")
            }
            if !before.hasCorrections, facts.hasCorrections {
                update(.correctionsAvailable, field: "hasCorrezioni")
            }
        }

        for (id, facts) in old.sorted(by: { $0.key < $1.key }) where new[id] == nil {
            // Sittings leave the list once they are over: normal, not news.
            guard let date = facts.date, date > now else {
                missing.remove(id)
                continue
            }
            if missing.contains(id) {
                missing.remove(id)
                updates.append(ExamUpdate(
                    kind: .withdrawn, examID: id, courseCode: facts.courseCode,
                    courseName: facts.courseName, detectedAt: now, source: .exams,
                    // An absence, confirmed twice — not a field saying so.
                    confidence: .high,
                    evidence: "iae:/v1/insegn c_appello=\(id) assente in due letture",
                    wasEnrolled: facts.enrolled, examDate: facts.date))
            } else {
                missing.insert(id)
            }
        }

        return updates
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
