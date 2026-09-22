import Foundation

/// Unread counts for the three buttons on a course's page, derived from
/// ``UpdateFeed``.
nonisolated struct CourseHubBadges: Sendable, Equatable {
    /// Unread announcements, shown on Avvisi.
    let announcements: Int
    /// Unread material, results, solutions and exam notices, shown on Materiali.
    let materials: Int
    /// Unread sitting and grade changes, shown on Appelli.
    let exams: Int

    /// Counts the unread items of each kind.
    ///
    /// - Parameters:
    ///   - items: This course's feed items.
    ///   - seenAt: When the course page was last opened, or `nil` if never — in which
    ///     case every item counts as unread.
    init(items: [FeedItem], seenAt: Date?) {
        let unread = items.filter { $0.isUnread(since: seenAt) }.map(\.update.kind)
        announcements = unread.count { $0 == .announcementPosted }
        materials = unread.count { [.resultsPosted, .solutionsPosted, .examNoticePosted, .materialAdded].contains($0) }
        exams = unread.count {
            [.discovered, .enrolmentOpened, .enrolled, .unenrolled, .roomPublished, .roomChanged, .dateChanged,
             .withdrawn, .gradePublished, .refusalOpened, .correctionsAvailable, .gradeRecorded].contains($0)
        }
    }
}
