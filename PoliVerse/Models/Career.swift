import Foundation

/// Aggregate career statistics — `GET {app}/v1/io-e-polimi/{matricola}`.
///
/// PoliFemo's `/rest/me/polimi/{matricola}` now 404s. The official web app
/// reads the same three numbers from `/v1/io-e-polimi/{registration_number}`:
///
/// ```js
/// WBe = (n, t) => bh.useQuery("get", "/v1/io-e-polimi/{registration_number}", …)
/// // rendered as: d.mean, d.given_cfu, "/" + d.planned_cfu
/// ```
///
/// so the field names survived the move even though the path did not.
nonisolated struct GradeBook: Sendable, Equatable, Codable {
    var mean: Double
    var earnedCFU: Int
    var plannedCFU: Int
    var examsPlanned: Int
    var examsSubscribed: Int
    var examsGiven: Int

    var progress: Double {
        guard plannedCFU > 0 else { return 0 }
        return min(Double(earnedCFU) / Double(plannedCFU), 1)
    }

    /// Degree mark out of 110, the number students actually care about.
    ///
    /// The standard conversion is `mean * 110 / 30`, before any bonus for
    /// thesis, timeliness or Erasmus — which vary by school, so this is a
    /// baseline, not a prediction.
    var baseGraduationMark: Double { mean * 110 / 30 }

    static let empty = GradeBook(
        mean: 0, earnedCFU: 0, plannedCFU: 0,
        examsPlanned: 0, examsSubscribed: 0, examsGiven: 0
    )
}

nonisolated struct GradeBookDTO: Decodable, Sendable {
    struct ExamStats: Decodable, Sendable {
        let planned: Int?
        let subscribed: Int?
        let given: Int?
    }

    let mean: Double?
    let given_cfu: Int?
    let planned_cfu: Int?
    /// Present on the old endpoint; the official app does not read it from the
    /// new one, so treat it as optional and fill the counts from
    /// ``ExamCountersDTO`` instead.
    let exam_stats: ExamStats?

    func toGradeBook() -> GradeBook {
        GradeBook(
            mean: mean ?? 0,
            earnedCFU: given_cfu ?? 0,
            plannedCFU: planned_cfu ?? 0,
            examsPlanned: exam_stats?.planned ?? 0,
            examsSubscribed: exam_stats?.subscribed ?? 0,
            examsGiven: exam_stats?.given ?? 0
        )
    }
}

/// `GET {iae}/v1/base/counters` — how many exams the student is signed up for
/// and how many results have been published.
///
/// Read straight off the official app's exams card:
///
/// ```js
/// children: v.num_iscriz   // IOEPOLIMI_EXAMS_ISCRIZ
/// children: v.num_esiti    // IOEPOLIMI_EXAMS_SOSTEN
/// ```
nonisolated struct ExamCountersDTO: Decodable, Sendable {
    let num_iscriz: Int?
    let num_esiti: Int?
}

// MARK: - Exam sessions

/// How an exam sitting relates to the student right now.
nonisolated enum ExamStatus: Sendable, Equatable {
    /// Enrolment window open, not enrolled.
    case open
    /// Enrolled, sitting still to come.
    case enrolled
    /// Enrolment window not open yet.
    case notYetOpen
    /// Window closed and not enrolled.
    case closed
    /// A mark has been published.
    case graded(ExamGrade)

    var label: String {
        switch self {
        case .open: "Iscrizioni aperte"
        case .enrolled: "Iscritto"
        case .notYetOpen: "Non ancora aperto"
        case .closed: "Iscrizioni chiuse"
        case .graded: "Esito disponibile"
        }
    }
}

/// A published exam result.
nonisolated struct ExamGrade: Sendable, Equatable {
    /// Numeric mark where one exists. Pass/fail and "idoneo" outcomes have none.
    let value: Int?
    /// The upstream text, e.g. "28", "30 e lode", "SUPERATO", "RESPINTO".
    let text: String
    let passed: Bool
    /// Whether the student may still refuse the mark.
    let refusable: Bool

    var display: String {
        if let value, text.localizedCaseInsensitiveContains("lode") { return "\(value)L" }
        return text
    }
}

/// One sitting of one exam.
nonisolated struct ExamSession: Identifiable, Sendable, Equatable {
    let id: Int
    let courseName: String
    let courseCode: String
    let teacher: String?
    let date: Date?
    let room: String?
    let enrolmentOpens: Date?
    let enrolmentCloses: Date?
    let enrolledCount: Int?
    let kind: String?
    let status: ExamStatus

    var grade: ExamGrade? {
        if case .graded(let grade) = status { return grade }
        return nil
    }
}

nonisolated struct ExamDTO: Decodable, Sendable {
    struct ActiveSubscription: Decodable, Sendable {
        let c_iscriz: Int?
        let verb_esito: String?
        let verb_esito_number: Int?
        let verb_positivo: String?
        let xverbEsito: String?
        let hasEsito: Bool?
        let rifiutabile: Bool?
    }

    let c_appello: Int
    let d_app: String?
    let ora_ok: String?
    let d_apertura: String?
    let d_chiusura: String?
    let numIscrittiAppello: Int?
    let descTipoAppello: String?
    let xaula: String?
    let iscrizioneAttiva: ActiveSubscription?
    let iscrizioniAperte: Bool?

    func toSession(courseName: String, courseCode: String, teacher: String?) -> ExamSession {
        let subscription = iscrizioneAttiva
        let status: ExamStatus

        if let subscription, subscription.hasEsito == true {
            // "positivo" is upstream's own pass flag; trust it over parsing the
            // mark text, which can be "SUPERATO", "IDONEO", "30 e lode", …
            let passed = (subscription.verb_positivo ?? "").uppercased().hasPrefix("S")
                || (subscription.verb_esito_number ?? 0) >= 18
            status = .graded(
                ExamGrade(
                    value: subscription.verb_esito_number,
                    text: subscription.xverbEsito ?? subscription.verb_esito ?? "—",
                    passed: passed,
                    refusable: subscription.rifiutabile ?? false
                )
            )
        } else if subscription != nil {
            status = .enrolled
        } else if iscrizioniAperte == true {
            status = .open
        } else if let opens = d_apertura.flatMap(PoliMiDate.parse), opens > .now {
            status = .notYetOpen
        } else {
            status = .closed
        }

        // The sitting's date and its time arrive in separate fields.
        var when = d_app.flatMap(PoliMiDate.parse)
        if let base = when, let time = ora_ok, !time.isEmpty {
            when = PoliMiDate.applying(time: time, to: base) ?? base
        }

        return ExamSession(
            id: c_appello,
            courseName: Course.normalise(courseName),
            courseCode: courseCode,
            teacher: teacher?.capitalized,
            date: when,
            room: xaula?.isEmpty == false ? xaula : nil,
            enrolmentOpens: d_apertura.flatMap(PoliMiDate.parse),
            enrolmentCloses: d_chiusura.flatMap(PoliMiDate.parse),
            enrolledCount: numIscrittiAppello,
            kind: descTipoAppello,
            status: status
        )
    }
}
