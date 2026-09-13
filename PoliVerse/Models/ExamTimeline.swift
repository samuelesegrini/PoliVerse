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
            switch update.kind {
            case .gradeRecorded, .resultsPosted, .solutionsPosted:
                return latestSitting(before: update, among: sittings)?.id == exam.id
            case .examNoticePosted:
                return nextSitting(after: update, among: sittings)?.id == exam.id
            case .announcementPosted:
                // Only a post the detector already tied to a sitting's date.
                guard let date = update.examDate else { return false }
                return exam.date == date && exam.isOf(courseCode: update.courseCode, courseName: update.courseName)
            default:
                return false
            }
        }
        entries += belonging.map {
            ExamTimelineEntry(
                id: $0.id, date: $0.detectedAt, title: $0.title, detail: $0.detail,
                source: [$0.sourceLabel, $0.confidenceNote].compactMap { $0 }.joined(separator: " · "),
                isFuture: false, update: $0)
        }

        return entries.sorted { $0.date < $1.date }
    }

    /// The libretto and WeBeep have no sitting id. A mark, a results file or
    /// solutions belong to the course's most recent sitting before they were
    /// seen — not to every earlier one, or a January fail would show
    /// February's pass.
    ///
    /// Matched by code or by name: the libretto's id is `c_insegn` or, when
    /// that is absent, a row id that shares nothing with `/v1/insegn`.
    ///
    /// Within ``ExamUpdatePolicy/resultsWindow``: a file of results posted a
    /// year after a sitting is not that sitting's.
    private static func latestSitting(before update: ExamUpdate, among sittings: [ExamSession]) -> ExamSession? {
        sittings
            .filter { $0.isOf(courseCode: update.courseCode, courseName: update.courseName) }
            .filter {
                guard let date = $0.date else { return false }
                return date <= update.detectedAt
                    && update.detectedAt.timeIntervalSince(date) <= ExamUpdatePolicy.resultsWindow
            }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// A notice about rooms or instructions belongs to the sitting ahead.
    private static func nextSitting(after update: ExamUpdate, among sittings: [ExamSession]) -> ExamSession? {
        sittings
            .filter { $0.isOf(courseCode: update.courseCode, courseName: update.courseName) }
            .filter {
                guard let date = $0.date else { return false }
                return date >= update.detectedAt
                    && date.timeIntervalSince(update.detectedAt) <= ExamUpdatePolicy.noticeHorizon
            }
            .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}
