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

// MARK: - Exam sessions

/// How an exam sitting relates to the student right now.
nonisolated enum ExamStatus: Sendable, Equatable, Codable {
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
nonisolated struct ExamGrade: Sendable, Equatable, Codable {
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
/// `Codable` so that sittings survive a launch offline, like the libretto
/// beside them: a student on a train should still see when their next exam is.
nonisolated struct ExamSession: Identifiable, Sendable, Equatable, Codable {
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
    /// Whether the marked script can be looked at on Servizi Online —
    /// `iscrizioneAttiva.hasCorrezioni`.
    var hasCorrections = false

    var grade: ExamGrade? {
        if case .graded(let grade) = status { return grade }
        return nil
    }

    /// Whether this sitting is of the given course.
    ///
    /// By code first; by name where the codes differ — WeBeep's title code,
    /// the libretto's `c_insegn` and `/v1/insegn`'s `c_insegn_piano` are not
    /// guaranteed to agree, while the names are normalised the same way.
    ///
    /// Neither comparison is made on a blank value. Comparing them plainly
    /// meant two *missing* codes counted as the same code, so one sitting that
    /// arrived without one matched every course that also lacked one — and,
    /// through ``ExamTimeline`` and the course screens, showed up under all of
    /// them at once. A value nobody has is not evidence that two things are
    /// the same.
    func isOf(courseCode: String, courseName: String) -> Bool {
        if isMeaningful(courseCode), isMeaningful(self.courseCode), courseCode == self.courseCode {
            return true
        }
        let name = Course.normalise(courseName)
        guard isMeaningful(name), isMeaningful(self.courseName) else { return false }
        return name.caseInsensitiveCompare(self.courseName) == .orderedSame
    }

    /// Blank, or one of the dashes these endpoints use for "not recorded".
    private func isMeaningful(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "—" && trimmed != "-"
    }
}
