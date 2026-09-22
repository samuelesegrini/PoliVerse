import Foundation

/// Finds the prove in itinere in what the Politecnico publishes.
///
/// Whether a course offers them is structured data on its scheda. Whether the student
/// sat one shows only where the lecturer ran it as a sitting with enrolment, whose
/// type then names it. How the parts count towards the exam is the lecturer's prose,
/// which ``sentences(in:)`` quotes rather than interprets.
nonisolated enum PartialExams {
    /// Whether a course offers partial exams.
    enum Policy: Sendable, Equatable {
        /// `offered` when the scheda names them, `none` when it says there are none, and
        /// `unknown` when it says neither.
        case offered, none, unknown
    }

    /// The Italian and English wordings a partial exam is named by.
    private static let mention = #"(in itinere|intermedi[ae]|parzial[ei]|midterm|mid-term|ongoing assessment|partial exam)"#

    /// Reads a course's policy off its scheda.
    ///
    /// A line denying partial exams wins over one naming them, so “senza prove in
    /// itinere” yields ``Policy/none``.
    ///
    /// - Parameters:
    ///   - assessment: The scheda's assessment lines.
    ///   - notes: The lecturer's free-text notes.
    /// - Returns: The policy, or ``Policy/unknown`` when neither mentions them.
    static func policy(assessment: [String], notes: String?) -> Policy {
        for line in assessment.map(fold) {
            if line.contains("senza prove in itinere") || line.contains("without") && matches(line) { return .none }
            if matches(line) { return .offered }
        }
        if let notes, matches(fold(notes)) { return .offered }
        return .unknown
    }

    /// The sentences of the lecturer's notes that mention partial exams, quoted
    /// verbatim.
    ///
    /// - Parameter notes: The lecturer's free-text notes.
    /// - Returns: The matching sentences, trimmed, in order.
    static func sentences(in notes: String?) -> [String] {
        guard let notes else { return [] }
        var found: [String] = []
        notes.enumerateSubstrings(in: notes.startIndex..., options: .bySentences) { sentence, _, _, _ in
            if let sentence, matches(fold(sentence)) {
                found.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return found
    }

    /// The sittings whose ``ExamSession/kind`` names a partial exam.
    ///
    /// - Parameter sessions: The sittings to filter.
    /// - Returns: The partial-exam sittings.
    static func sittings(_ sessions: [ExamSession]) -> [ExamSession] {
        sessions.filter { $0.kind.map { matches(fold($0)) } ?? false }
    }

    /// The exam entries on the timetable whose title or notes name a partial exam.
    ///
    /// - Parameter events: The agenda entries to filter.
    /// - Returns: The matching entries.
    static func agendaEvents(_ events: [AgendaEvent]) -> [AgendaEvent] {
        events.filter { $0.kind == .exam && matches(fold([$0.title, $0.details ?? ""].joined(separator: " "))) }
    }

    /// The results files posted on WeBeep whose name names a partial exam.
    ///
    /// - Parameter updates: The updates to filter.
    /// - Returns: The matching updates.
    static func resultsFiles(_ updates: [ExamUpdate]) -> [ExamUpdate] {
        updates.filter { $0.kind == .resultsPosted && matches(fold($0.newValue ?? "")) }
    }

    /// Whether folded text mentions a partial exam.
    ///
    /// - Parameter folded: Text already passed through ``fold(_:)``.
    /// - Returns: `true` on a match.
    private static func matches(_ folded: String) -> Bool {
        folded.range(of: mention, options: .regularExpression) != nil
    }

    /// Folds text to ignore case and diacritics, then lower-cases it.
    ///
    /// - Parameter text: The text to fold.
    /// - Returns: The comparable form.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}
