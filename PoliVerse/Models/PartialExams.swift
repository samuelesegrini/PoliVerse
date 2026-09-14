import Foundation

/// Prove in itinere, from what the Politecnico actually publishes.
///
/// Whether a course has them is structured data on the scheda ("senza prove
/// in itinere"). Whether the student sat one shows only where the teacher ran
/// it as a sitting with enrolment, whose type then names it. How the parts
/// count towards the exam is the teacher's prose: quoted, never computed.
nonisolated enum PartialExams {
    enum Policy: Sendable, Equatable {
        case offered, none, unknown
    }

    private static let mention = #"(in itinere|intermedi[ae]|parzial[ei]|midterm|mid-term|ongoing assessment|partial exam)"#

    static func policy(assessment: [String], notes: String?) -> Policy {
        for line in assessment.map(fold) {
            if line.contains("senza prove in itinere") || line.contains("without") && matches(line) { return .none }
            if matches(line) { return .offered }
        }
        if let notes, matches(fold(notes)) { return .offered }
        return .unknown
    }

    /// The sentences of the teacher's notes that talk about partial exams.
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

    static func sittings(_ sessions: [ExamSession]) -> [ExamSession] {
        sessions.filter { $0.kind.map { matches(fold($0)) } ?? false }
    }

    /// Exams on the agenda whose title or notes name a partial exam.
    static func agendaEvents(_ events: [AgendaEvent]) -> [AgendaEvent] {
        events.filter { $0.kind == .exam && matches(fold([$0.title, $0.details ?? ""].joined(separator: " "))) }
    }

    /// Results files posted on WeBeep whose name names a partial exam.
    static func resultsFiles(_ updates: [ExamUpdate]) -> [ExamUpdate] {
        updates.filter { $0.kind == .resultsPosted && matches(fold($0.newValue ?? "")) }
    }

    private static func matches(_ folded: String) -> Bool {
        folded.range(of: mention, options: .regularExpression) != nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}
