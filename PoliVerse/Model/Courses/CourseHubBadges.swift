import Foundation

/// Unread counts for the course page's buttons, from the update feed: new
/// announcements on Avvisi, new files on Materiali, exam changes on Appelli.
nonisolated struct CourseHubBadges: Sendable, Equatable {
    let announcements: Int
    let materials: Int
    let exams: Int

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
