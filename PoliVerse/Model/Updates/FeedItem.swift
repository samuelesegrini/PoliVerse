import Foundation

/// One row of the updates feed.
///
/// The log keeps every sighting, because notifications and budgets are
/// counted on sightings. A person reads facts: a mark and its refusal window
/// seen together are one thing, and a mark read from a file is old news once
/// the exam services publish the official one (§11.4, §10.4).
nonisolated struct FeedItem: Identifiable, Sendable, Equatable {
    let update: ExamUpdate
    /// Said after the detail, e.g. that the mark can be refused.
    let note: String?
    /// A file's mark the official record has since published.
    let isSuperseded: Bool

    var id: String { update.id }

    var detail: String? {
        isSuperseded ? String(localized: "Voto confermato sui Servizi Online") : update.detail
    }

    /// Rows for the given updates, in their order.
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

    /// A course's own rows: matched by code, or by name where the sources
    /// give the same teaching different codes (§3) — only then, so two
    /// teachings that share a name but both have a real code stay apart.
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

    /// Rows the student has not seen: newer than their last visit, and not a
    /// file's mark the official one has already replaced.
    static func unreadCount(_ items: [FeedItem], seenAt: Date?) -> Int {
        items.filter { $0.isUnread(since: seenAt) }.count
    }

    func isUnread(since seenAt: Date?) -> Bool {
        !isSuperseded && update.detectedAt > (seenAt ?? .distantPast)
    }

    /// Sightings this close together are the same refresh.
    static let foldWindow: TimeInterval = 3600

    private static func mark(for refusal: ExamUpdate, in updates: [ExamUpdate]) -> ExamUpdate? {
        updates.first {
            $0.kind == .gradePublished && $0.examID == refusal.examID
                && abs($0.detectedAt.timeIntervalSince(refusal.detectedAt)) < foldWindow
        }
    }
}
