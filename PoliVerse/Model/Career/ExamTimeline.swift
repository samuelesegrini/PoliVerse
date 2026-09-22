import Foundation

/// One line of a sitting's timeline.
nonisolated struct ExamTimelineEntry: Identifiable, Sendable, Equatable {
    /// The milestone's key within the sitting, or the update's own id.
    let id: String
    /// When the line is placed: the milestone's date, or when the update was noticed.
    let date: Date
    /// What the line says.
    let title: String
    /// A second line, such as the room.
    let detail: String?
    /// Where the fact comes from, shown so that nothing inferred passes as official.
    let source: String
    /// Whether the line is still ahead.
    let isFuture: Bool
    /// The update behind the line, or `nil` for a date read off the sitting itself.
    let update: ExamUpdate?
}

/// Builds a sitting's timeline from the dates it carries and the updates the app has
/// noticed.
nonisolated enum ExamTimeline {
    /// The timeline for one sitting, oldest first.
    ///
    /// Three milestones come from the sitting itself — enrolment opening, enrolment
    /// closing and the exam — and are attributed to the exams service. Updates are then
    /// added: those naming this sitting directly, plus marks, results and solutions tied
    /// to it by ``latestSitting(before:among:)``, exam notices tied by
    /// ``nextSitting(after:among:)``, and announcements the detector already tied to a
    /// sitting's date.
    ///
    /// - Parameters:
    ///   - exam: The sitting to build the timeline for.
    ///   - sittings: Every sitting known, so a libretto mark reaches the right one.
    ///   - updates: The updates the app has noticed.
    ///   - now: The moment that decides ``ExamTimelineEntry/isFuture``.
    /// - Returns: The lines, sorted by date.
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
                    detail: key == "exam" ? exam.room.map(RoomNaming.sentence) : nil,
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

    /// The sitting a mark, a results file or a set of solutions belongs to.
    ///
    /// Neither the libretto nor WeBeep carries a sitting id, so the update is tied to
    /// the course's most recent sitting before it was noticed — not to every earlier
    /// one, or a January failure would show February's pass. The match is capped at
    /// ``ExamUpdatePolicy/resultsWindow``, since results posted a year after a sitting
    /// are not that sitting's.
    ///
    /// - Parameters:
    ///   - update: The update to place.
    ///   - sittings: Every sitting known.
    /// - Returns: The sitting, or `nil` when none fits.
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

    /// The sitting a notice about rooms or instructions belongs to: the course's next
    /// sitting within ``ExamUpdatePolicy/noticeHorizon``.
    ///
    /// - Parameters:
    ///   - update: The update to place.
    ///   - sittings: Every sitting known.
    /// - Returns: The sitting, or `nil` when none fits.
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
