import Foundation

/// One line of a sitting's timeline.
nonisolated struct ExamTimelineEntry: Identifiable, Sendable, Equatable {
    let id: String
    let date: Date
    let title: String
    let detail: String?
    /// Where the fact comes from, shown so nothing guessed passes as official.
    let source: String
    let isFuture: Bool
    /// The update behind this line; nil for a date read off the sitting.
    let update: ExamUpdate?
}

/// Builds a sitting's timeline from what the app noticed and the dates the
/// sitting already carries.
nonisolated enum ExamTimeline {
    /// - Parameter sittings: every sitting known, so a libretto mark can be
    ///   given to the right one.
    static func entries(
        for exam: ExamSession, sittings: [ExamSession], updates: [ExamUpdate], now: Date
    ) -> [ExamTimelineEntry] {
        let official = ExamUpdate.Source.exams.label

        let milestones: [(String, String, Date?)] = [
            ("opens", String(localized: "Apertura iscrizioni"), exam.enrolmentOpens),
            ("closes", String(localized: "Chiusura iscrizioni"), exam.enrolmentCloses),
            ("exam", String(localized: "Esame"), exam.date),
        ]
        var entries = milestones.compactMap { key, title, date in
            date.map {
                ExamTimelineEntry(
                    id: "\(exam.id)-\(key)", date: $0, title: title,
                    detail: key == "exam" ? exam.room.map { String(localized: "Aula \($0)") } : nil,
                    source: official, isFuture: $0 > now, update: nil)
            }
        }

        let belonging = updates.filter { update in
            if update.examID == exam.id { return true }
            guard update.kind == .gradeRecorded else { return false }
            return latestSitting(before: update, among: sittings)?.id == exam.id
        }
        entries += belonging.map {
            ExamTimelineEntry(
                id: $0.id, date: $0.detectedAt, title: $0.title, detail: $0.detail,
                source: [$0.sourceLabel, $0.confidenceNote].compactMap { $0 }.joined(separator: " · "),
                isFuture: false, update: $0)
        }

        return entries.sorted { $0.date < $1.date }
    }

    /// The libretto has no sitting id. Its mark belongs to the course's most
    /// recent sitting before the mark was seen — not to every earlier one,
    /// or a January fail would show February's pass.
    ///
    /// Matched by code or by name: the libretto's id is `c_insegn` or, when
    /// that is absent, a row id that shares nothing with `/v1/insegn`.
    private static func latestSitting(before update: ExamUpdate, among sittings: [ExamSession]) -> ExamSession? {
        sittings
            .filter { $0.courseCode == update.courseCode || $0.courseName == update.courseName }
            .filter { ($0.date ?? .distantFuture) <= update.detectedAt }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
}
