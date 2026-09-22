import Foundation

/// One row of the updates feed.
///
/// The log keeps every sighting, because notifications and budgets are counted on
/// sightings. A person reads facts instead: a mark and its refusal window seen together
/// are one row, and a mark read out of a file is old news once the exam services publish
/// the official one.
nonisolated struct FeedItem: Identifiable, Sendable, Equatable {
    /// The sighting this row shows.
    let update: ExamUpdate
    /// A line said after the detail, such as that the mark can still be refused.
    let note: String?
    /// Whether this is a mark read from a file that the official record has since published.
    /// A superseded row never counts as unread.
    let isSuperseded: Bool

    /// The sighting's id.
    var id: String { update.id }

    /// The row's detail line, or a note that the mark has been confirmed on Servizi Online
    /// when the row has been superseded.
    var detail: String? {
        isSuperseded ? String(localized: "Voto confermato sui Servizi Online") : update.detail
    }

    /// Rows for the given updates, in their order.
    ///
    /// A refusal window seen with its mark is dropped and folded into the mark's row. A mark
    /// read out of a file is marked superseded once the official one is present.
    ///
    /// - Parameter updates: The sightings to show.
    /// - Returns: The rows.
    static func items(from updates: [ExamUpdate]) -> [FeedItem] {
        updates.compactMap { update in
            switch update.kind {
            case .refusalOpened where mark(for: update, in: updates) != nil:
                return nil

            case .gradePublished:
                let folded = updates.contains {
                    $0.kind == .refusalOpened && $0.examID == update.examID
                        && abs($0.detectedAt.timeIntervalSince(update.detectedAt)) < foldWindow
                }
                return FeedItem(update: update,
                                note: folded ? String(localized: "Puoi rifiutarlo") : nil,
                                isSuperseded: false)

            case .resultsPosted where update.lookup?.found == true:
                let official = updates.contains { ExamUpdatePolicy.confirms($0, fileGrade: update) }
                return FeedItem(update: update, note: nil, isSuperseded: official)

            default:
                return FeedItem(update: update, note: nil, isSuperseded: false)
            }
        }
    }

    /// One course's rows.
    ///
    /// Matched by teaching code, or by name where the sources give the same teaching
    /// different codes — but only then, so two teachings that share a name and both have a
    /// real code stay apart.
    ///
    /// - Parameters:
    ///   - updates: The sightings to filter.
    ///   - course: The course whose rows to show.
    /// - Returns: The rows.
    static func items(from updates: [ExamUpdate], for course: Course) -> [FeedItem] {
        let codes = Set([course.id, course.code, course.teachingCode].compactMap { $0 })
        let name = MutedCourse.key(course.name)
        let isTeachingCode = { (code: String) in code.range(of: "^[0-9]{6}$", options: .regularExpression) != nil }
        return items(from: updates.filter { update in
            if codes.contains(update.courseCode) { return true }
            let bothCoded = isTeachingCode(update.courseCode) && course.teachingCode != nil
            return !bothCoded && MutedCourse.key(update.courseName) == name
        })
    }

    /// How many rows the student has not seen.
    ///
    /// - Parameters:
    ///   - items: The rows to count.
    ///   - seenAt: When the feed was last opened, or `nil` if never.
    /// - Returns: The count.
    static func unreadCount(_ items: [FeedItem], seenAt: Date?) -> Int {
        items.filter { $0.isUnread(since: seenAt) }.count
    }

    /// Whether this row is newer than the student's last visit and not superseded.
    ///
    /// - Parameter seenAt: When the feed was last opened, or `nil` if never.
    /// - Returns: `true` when the row counts as unread.
    func isUnread(since seenAt: Date?) -> Bool {
        !isSuperseded && update.detectedAt > (seenAt ?? .distantPast)
    }

    /// Sightings this close together came from the same refresh, and so are one fact.
    static let foldWindow: TimeInterval = 3600

    /// The published mark a refusal window belongs to, when both were seen in the same
    /// refresh.
    ///
    /// - Parameters:
    ///   - refusal: The refusal-window sighting.
    ///   - updates: The sightings to search.
    /// - Returns: The mark, or `nil` when it was seen at another time or not at all.
    private static func mark(for refusal: ExamUpdate, in updates: [ExamUpdate]) -> ExamUpdate? {
        updates.first {
            $0.kind == .gradePublished && $0.examID == refusal.examID
                && abs($0.detectedAt.timeIntervalSince(refusal.detectedAt)) < foldWindow
        }
    }
}
