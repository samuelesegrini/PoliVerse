import Foundation

/// Something that changed about the student's exams or course pages since the app last
/// looked.
///
/// The Politecnico publishes no change feed: its services answer what is true now. An
/// update is the difference between two such answers, recorded once, with where it came
/// from — ``source`` and ``evidence`` — and how sure the reading is — ``confidence``.
///
/// ``ExamChangeDetector`` produces the updates read from the exam services and the
/// libretto; ``MaterialChangeDetector``, ``AnnouncementDetector`` and
/// ``AssignmentDetector`` produce the ones read from WeBeep. ``ExamUpdatePolicy``
/// decides what the student is told.
///
/// See `docs/academic-intelligence-layer.md` §6 for the event model.
nonisolated struct ExamUpdate: Identifiable, Sendable, Equatable, Codable {
    /// What kind of change this is. Every kind belongs to an ``UpdateCategory``, which is
    /// what the student can switch off.
    nonisolated enum Kind: String, Sendable, Codable, CaseIterable {
        /// A new sitting appeared, its enrolment window opened, the student enrolled, or their
        /// enrolment was cancelled.
        case discovered, enrolmentOpened, enrolled, unenrolled
        /// A sitting's room was published or changed, its date moved, or the sitting itself was
        /// withdrawn.
        case roomPublished, roomChanged, dateChanged, withdrawn
        /// A mark was published, became refusable, had its script made inspectable, or was
        /// recorded in the libretto.
        case gradePublished, refusalOpened, correctionsAvailable, gradeRecorded
        /// A file appeared on a WeBeep course page, tagged from its name by
        /// ``DocumentClassifier``: a list of results, worked solutions, an exam notice, or
        /// ordinary material.
        case resultsPosted, solutionsPosted, examNoticePosted, materialAdded
        /// A new post in a course's announcements forum.
        case announcementPosted
        /// A WeBeep assignment appeared, or its deadline moved. ``examDate`` carries the
        /// deadline.
        case assignmentAdded, deadlineChanged

        /// The SF Symbol shown beside the update.
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
            case .announcementPosted: "text.bubble"
            case .assignmentAdded: "tray.and.arrow.up"
            case .deadlineChanged: "clock.badge.exclamationmark"
            }
        }
    }

    /// Which service the change was read from.
    nonisolated enum Source: String, Sendable, Codable {
        /// The exam registration service, `iae/v1/insegn`.
        case exams
        /// The libretto, `elencoinsegnamenti`.
        case libretto
        /// A WeBeep course page, `core_course_get_contents` and the forum calls.
        case webeep

        /// The service's name as the student is shown it.
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
        /// Inferred from an absence, or joined by teaching code — right almost always, but not
        /// a field saying so.
        case high
        /// Read from a name that fits more than one meaning. Never pushed on its own.
        case probable
    }

    /// What the student is told, decided once when the update is recorded. See
    /// ``ExamUpdatePolicy``.
    nonisolated enum Delivery: String, Sendable, Codable {
        /// Shown in the app, never pushed.
        case inApp
        /// Pushed now, within the daily allowance.
        case push
        /// Pushed now and never rationed, but not allowed through Focus.
        case priority
        /// Pushed now and allowed through Focus.
        case urgent
        /// Folded into the evening summary.
        case digest
        /// Held back by quiet hours and summarised in the morning.
        case morning

        /// Whether this delivery pushes a notification now.
        var isImmediate: Bool { self == .push || self == .priority || self == .urgent }
    }

    /// Stable for the same change: seeing it twice in quick succession produces the same
    /// id, so the log can refuse the second copy.
    ///
    /// Built from the kind, the sitting or teaching, and either an explicit identity or the
    /// new value.
    let id: String
    /// What kind of change this is.
    let kind: Kind
    /// The sitting this concerns, where the change was read from a sitting. `nil` for
    /// anything read from the libretto or from WeBeep, which carry no sitting id.
    let examID: Int?
    /// The teaching code, or the libretto row's id for a recorded mark.
    let courseCode: String
    /// The teaching's name.
    let courseName: String
    /// When the app noticed, which is what the feed orders by.
    let detectedAt: Date
    /// Which service it was read from.
    let source: Source
    /// How sure the reading is. See ``confidenceNote``.
    let confidence: Confidence
    /// Which call and field said so, for example `iae:/v1/insegn c_appello=123 xaula`.
    let evidence: String
    /// What the field said before, where there was a previous value.
    let oldValue: String?
    /// What it says now — a room, a mark, a file name, or a count for a collapsed update.
    let newValue: String?
    /// Whether the student was signed up when this was seen, which is what makes a room
    /// change urgent rather than trivia.
    let wasEnrolled: Bool
    /// The sitting this concerns, or the deadline for an assignment update.
    let examDate: Date?
    /// What the student is told. Set by ``ExamUpdatePolicy`` when the update is recorded.
    var delivery: Delivery = .inApp
    /// What a results file said about this student, when they allowed the app to read one.
    /// Nothing about anyone else.
    var lookup: ResultsLookup? = nil

    /// Records one change.
    ///
    /// - Parameters:
    ///   - kind: What kind of change this is.
    ///   - examID: The sitting it concerns, where there is one.
    ///   - courseCode: The teaching code.
    ///   - courseName: The teaching's name.
    ///   - detectedAt: When the app noticed.
    ///   - source: Which service it was read from.
    ///   - confidence: How sure the reading is.
    ///   - evidence: Which call and field said so.
    ///   - oldValue: What the field said before.
    ///   - newValue: What it says now.
    ///   - identity: Stands in for `newValue` in ``id`` when the value alone would call two
    ///     different changes the same — a file re-uploaded under its own name.
    ///   - wasEnrolled: Whether the student was signed up.
    ///   - examDate: The sitting, or the deadline.
    ///   - delivery: What the student is told.
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

    /// The update's headline.
    ///
    /// Worded as what was seen rather than as what it probably means: a file named “Esiti”
    /// is reported as a results file having been posted, not as the student's mark — unless
    /// ``lookup`` says their own line was in it.
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
        case .resultsPosted where lookup?.found == true: String(localized: "Sei negli esiti")
        case .resultsPosted: String(localized: "Pubblicato un file di esiti")
        case .solutionsPosted: String(localized: "Pubblicate le soluzioni")
        case .examNoticePosted: String(localized: "Nuovo avviso d'esame")
        case .materialAdded: String(localized: "Nuovo materiale")
        case .announcementPosted: String(localized: "Nuovo annuncio del docente")
        case .assignmentAdded: String(localized: "Nuova consegna")
        case .deadlineChanged: String(localized: "Scadenza della consegna cambiata")
        }
    }

    /// One line of detail beyond the teaching's name, or `nil` where there is none.
    ///
    /// A replaced WeBeep file says so. A results file the student was not found in says
    /// that too, rather than leaving them to wonder.
    var detail: String? {
        switch kind {
        case .roomPublished: newValue.map(RoomNaming.sentence)
        case .roomChanged:
            if let oldValue, let newValue { String(localized: "Da \(oldValue) a \(newValue)") } else { nil }
        case .gradePublished, .gradeRecorded: newValue.map { String(localized: "Voto: \($0)") }
        case .resultsPosted where lookup?.found == true:
            lookup?.grade.map { String(localized: "Voto nel file: \($0)") } ?? newValue
        case .resultsPosted where lookup?.looksLikeResults == true:
            String(localized: "Non compari nel file")
        case .resultsPosted, .solutionsPosted, .examNoticePosted:
            // A file put up again over an old one, or under a new name.
            isReplacement ? newValue.map { String(localized: "\($0) (nuova versione)") } : newValue
        case .materialAdded: newValue.flatMap(Int.init).map { String(localized: "\($0) nuovi file") }
        case .announcementPosted: newValue
        case .assignmentAdded, .deadlineChanged:
            [newValue, examDate.map { String(localized: "entro \($0.formatted(Self.deadlineStyle))") }]
                .compactMap { $0 }.joined(separator: " · ")
        default: nil
        }
    }

    /// An abbreviated date and short time, in Rome, for a deadline.
    private static var deadlineStyle: Date.FormatStyle {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = PoliMiDate.romeCalendar.timeZone
        return style
    }

    /// Where the update came from, as the student is shown it. More specific than
    /// ``Source/label`` for forum posts and assignments, which come from different parts of
    /// WeBeep.
    var sourceLabel: String {
        switch kind {
        case .announcementPosted: String(localized: "WeBeep · forum Annunci")
        case .assignmentAdded, .deadlineChanged: String(localized: "WeBeep · consegne")
        default: source.label
        }
    }

    /// The same sighting read as another kind, once a file's contents say what its name did
    /// not.
    ///
    /// A “solutions” file holding a table of marks is results; a “results” file with no
    /// table is a notice. The original identity is preserved, so the log still recognises
    /// the two as one sighting.
    ///
    /// - Parameters:
    ///   - kind: What the file turned out to be.
    ///   - lookup: What the file said about this student.
    /// - Returns: The reclassified update.
    func reclassified(as kind: Kind, lookup: ResultsLookup?) -> ExamUpdate {
        var copy = ExamUpdate(
            kind: kind, examID: examID, courseCode: courseCode, courseName: courseName,
            detectedAt: detectedAt, source: source, confidence: confidence, evidence: evidence,
            oldValue: oldValue, newValue: newValue,
            identity: id.split(separator: "|", maxSplits: 2).last.map(String.init),
            wasEnrolled: wasEnrolled, examDate: examDate, delivery: delivery)
        copy.lookup = lookup
        return copy
    }

    /// Whether this is a WeBeep file that replaced an earlier one of the same kind.
    var isReplacement: Bool { source == .webeep && oldValue != nil }

    /// A line said out loud when the fact was inferred rather than read, so it never looks
    /// as certain as a field.
    ///
    /// `nil` for ``Confidence/exact``. A mark read out of a file always carries one, since
    /// the exam services have the last word.
    var confidenceNote: String? {
        if lookup?.found == true {
            return String(localized: "Letto dal file: da confermare sui Servizi Online")
        }
        return switch (confidence, kind) {
        case (.exact, _): nil
        case (.high, .withdrawn): String(localized: "Dedotto: assente in due letture consecutive")
        case (.high, .resultsPosted), (.high, .solutionsPosted), (.high, .examNoticePosted),
             (.high, .materialAdded): String(localized: "Dedotto dal nome del file")
        case (.probable, _): String(localized: "Dal nome del file, ambiguo")
        case (.high, _): String(localized: "Dedotto: collegato per insegnamento")
        }
    }
}

/// The kinds of news the student can switch off one at a time. See
/// `docs/academic-intelligence-layer.md` §13.
nonisolated enum UpdateCategory: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Marks and results files; sittings' rooms and dates; enrolment windows; lecturers'
    /// announcements, notices and solutions; and course material and hand-ins.
    case results, roomsAndDates, enrolments, teachers, coursework

    /// The raw value.
    var id: String { rawValue }

    /// Every ``ExamUpdate/Kind`` that belongs to this category.
    var kinds: Set<ExamUpdate.Kind> {
        Set(ExamUpdate.Kind.allCases.filter { $0.category == self })
    }

    /// The category's name in Impostazioni.
    var label: String {
        switch self {
        case .results: String(localized: "Esiti e voti")
        case .roomsAndDates: String(localized: "Aule e date degli appelli")
        case .enrolments: String(localized: "Iscrizioni agli appelli")
        case .teachers: String(localized: "Annunci, avvisi e soluzioni")
        case .coursework: String(localized: "Materiali e consegne")
        }
    }
}

/// Which category a kind belongs to.
extension ExamUpdate.Kind {
    /// The category this kind belongs to.
    ///
    /// A `switch` over every case, so a new kind does not compile until it has been given
    /// one.
    nonisolated var category: UpdateCategory {
        switch self {
        case .gradePublished, .refusalOpened, .gradeRecorded, .resultsPosted, .correctionsAvailable: .results
        case .roomPublished, .roomChanged, .dateChanged, .withdrawn: .roomsAndDates
        case .discovered, .enrolmentOpened, .enrolled, .unenrolled: .enrolments
        case .announcementPosted, .examNoticePosted, .solutionsPosted: .teachers
        case .materialAdded, .assignmentAdded, .deadlineChanged: .coursework
        }
    }
}

/// What ``ExamChangeDetector`` remembers between looks.
nonisolated struct ExamWatchState: Sendable, Equatable, Codable {
    /// The last good reading of the sittings, by sitting id. `nil` until one has been seen,
    /// which is what makes the first look a silent baseline.
    var exams: [Int: ExamFacts]?
    /// Future sittings absent from the latest answer, waiting for a second miss before they
    /// count as withdrawn.
    var missing: Set<Int> = []
    /// Libretto rows by id, `true` when passed. `nil` until one reading has been seen.
    var libretto: [String: Bool]?
}

/// The parts of a sitting whose change is worth noticing, normalised for comparison.
nonisolated struct ExamFacts: Sendable, Equatable, Codable {
    /// The sitting's id.
    let id: Int
    /// The teaching code.
    let courseCode: String
    /// The teaching's name.
    let courseName: String
    /// When the sitting is held.
    let date: Date?
    /// The room, trimmed, with an empty value treated as absent.
    let room: String?
    /// Whether the enrolment window is open.
    let enrolmentOpen: Bool
    /// Whether the student is signed up. A published mark counts, since it implies a
    /// registration.
    let enrolled: Bool
    /// Whether a mark has been published.
    let graded: Bool
    /// The mark as it is displayed.
    let gradeText: String?
    /// Whether the mark may still be refused.
    let refusable: Bool
    /// Whether the marked script can be inspected.
    let hasCorrections: Bool

    /// Reduces a sitting to the facts worth watching.
    ///
    /// - Parameter session: The sitting as the service describes it.
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

/// Compares two looks at the exam services and the libretto, and says what changed.
///
/// Pure, and tested as such. The rules that matter most are about when not to compare:
/// the first look, a failed request and the empty answer the services give between
/// sessions all leave the state alone and report nothing, because a false “sitting
/// withdrawn” is worse than a late true one.
///
/// A withdrawal needs two consecutive misses, and the previous facts are kept in the
/// meantime so the withdrawal still has a name and a date to report.
nonisolated enum ExamChangeDetector {
    /// What one comparison produced.
    struct Result: Sendable {
        /// What changed. Empty on a baseline look or a failed request.
        let updates: [ExamUpdate]
        /// What to remember for the next look.
        let state: ExamWatchState
    }

    /// Compares a look at the exam services and the libretto against the previous one.
    ///
    /// - Parameters:
    ///   - previous: What was remembered from the last look, or `nil` for the first.
    ///   - sessions: The sittings, or `nil` when that request failed. An empty array is
    ///     treated the same as a failure, since the services answer empty between sessions.
    ///   - libretto: The libretto, or `nil` when that request failed.
    ///   - now: The moment of this look.
    /// - Returns: What changed, and what to remember.
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

    /// Compares two readings of the sittings.
    ///
    /// A sitting seen for the first time is news only when it is still ahead. A sitting
    /// absent from the new reading is news only when it was still ahead and has now been
    /// missing twice — sittings leave the list once they are over, which is normal.
    ///
    /// - Parameters:
    ///   - old: The previous reading, by sitting id.
    ///   - new: The current reading.
    ///   - missing: Sittings awaiting a second miss, updated in place.
    ///   - now: The moment of this look.
    /// - Returns: What changed, ordered by sitting id.
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

/// Treating an empty string as absent.
private extension String {
    /// The string, or `nil` when it is empty.
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
