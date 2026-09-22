import Foundation

/// The aggregate career figures, from `GET {app}/v1/io-e-polimi/{matricola}`.
nonisolated struct GradeBook: Sendable, Equatable, Codable {
    /// The credit-weighted average of the recorded marks, out of 30.
    var mean: Double
    /// Credits already earned.
    var earnedCFU: Int
    /// Credits the study plan totals.
    var plannedCFU: Int
    /// Exams the study plan contains.
    var examsPlanned: Int
    /// Sittings the student is currently enrolled in.
    var examsSubscribed: Int
    /// Exams with a recorded result.
    var examsGiven: Int

    /// ``earnedCFU`` as a fraction of ``plannedCFU``, clamped to 1. Zero when the plan
    /// totals no credits.
    var progress: Double {
        guard plannedCFU > 0 else { return 0 }
        return min(Double(earnedCFU) / Double(plannedCFU), 1)
    }

    /// The degree mark out of 110 implied by ``mean``.
    ///
    /// The standard conversion, before any bonus for the thesis, for finishing on time
    /// or for an Erasmus period — all of which vary by school, so this is a baseline
    /// rather than a prediction.
    var baseGraduationMark: Double { mean * 110 / 30 }

    /// Every figure at zero, for a career with nothing recorded yet.
    static let empty = GradeBook(
        mean: 0, earnedCFU: 0, plannedCFU: 0,
        examsPlanned: 0, examsSubscribed: 0, examsGiven: 0
    )
}

// MARK: - Exam sessions

/// How an exam sitting relates to the student right now.
nonisolated enum ExamStatus: Sendable, Equatable, Codable {
    /// The enrolment window is open and the student is not enrolled.
    case open
    /// Enrolled, with the sitting still to come.
    case enrolled
    /// The enrolment window has not opened yet.
    case notYetOpen
    /// The enrolment window has closed and the student did not enrol.
    case closed
    /// A mark has been published, carrying it.
    case graded(ExamGrade)

    /// The status as it appears on screen.
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
    /// The numeric mark, where there is one. Pass/fail and “idoneo” outcomes have none.
    let value: Int?
    /// The upstream wording, for example `"28"`, `"30 e lode"`, `"SUPERATO"` or
    /// `"RESPINTO"`.
    let text: String
    /// Whether the exam was passed.
    let passed: Bool
    /// Whether the student may still refuse the mark.
    let refusable: Bool

    /// The mark as it is shown: `"30L"` for a mark with honours, and ``text`` otherwise.
    var display: String {
        if let value, text.localizedCaseInsensitiveContains("lode") { return "\(value)L" }
        return text
    }
}

/// One sitting of one exam.
///
/// `Codable`, so sittings survive a launch offline alongside the libretto: a student
/// on a train should still see when their next exam is.
nonisolated struct ExamSession: Identifiable, Sendable, Equatable, Codable {
    /// The sitting's upstream identifier.
    let id: Int
    /// The teaching's name.
    let courseName: String
    /// The teaching's code, as the exams endpoint spells it.
    let courseCode: String
    /// The examining lecturer, where recorded.
    let teacher: String?
    /// When the sitting is held, where recorded.
    let date: Date?
    /// Where it is held, once published.
    let room: String?
    /// When the enrolment window opens.
    let enrolmentOpens: Date?
    /// When the enrolment window closes.
    let enrolmentCloses: Date?
    /// How many students are enrolled, where published.
    let enrolledCount: Int?
    /// The sitting's type as upstream words it, which is what names a partial exam. See
    /// ``PartialExams/sittings(_:)``.
    let kind: String?
    /// How the sitting relates to the student.
    let status: ExamStatus
    /// Whether the marked script can be inspected on Servizi Online.
    var hasCorrections = false

    /// The published mark, or `nil` in any status but ``ExamStatus/graded(_:)``.
    var grade: ExamGrade? {
        if case .graded(let grade) = status { return grade }
        return nil
    }

    /// Whether this sitting belongs to a given teaching.
    ///
    /// Matched by code first, then by normalised name, since WeBeep's title code, the
    /// libretto's row id and the exams endpoint's plan code are not guaranteed to agree
    /// while the names normalise alike.
    ///
    /// Neither comparison is made on a blank value: two missing codes are not evidence
    /// that two teachings are the same, and treating them as equal would match one
    /// sitting to every teaching that also lacks a code.
    ///
    /// - Parameters:
    ///   - courseCode: The teaching's code, as the caller knows it.
    ///   - courseName: The teaching's name.
    /// - Returns: `true` when both name the same teaching.
    func isOf(courseCode: String, courseName: String) -> Bool {
        if isMeaningful(courseCode), isMeaningful(self.courseCode), courseCode == self.courseCode {
            return true
        }
        let name = Course.normalise(courseName)
        guard isMeaningful(name), isMeaningful(self.courseName) else { return false }
        return name.caseInsensitiveCompare(self.courseName) == .orderedSame
    }

    /// Whether a value is worth comparing: not blank, and not one of the dashes these
    /// endpoints use for “not recorded”.
    ///
    /// - Parameter value: The value to test.
    /// - Returns: `true` when it carries information.
    private func isMeaningful(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "—" && trimmed != "-"
    }
}
