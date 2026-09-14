import Foundation
import Testing
@testable import PoliVerse

/// Unread counts on the course page's buttons, from the existing feed.
@Suite("Course hub badges")
struct CourseHubBadgeTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func item(_ kind: ExamUpdate.Kind, minutesAgo: Double, id: String) -> FeedItem {
        FeedItem.items(from: [ExamUpdate(
            kind: kind, examID: nil, courseCode: "F1", courseName: "Fisica",
            detectedAt: now.addingTimeInterval(-minutesAgo * 60), source: .webeep,
            evidence: "test", newValue: id, wasEnrolled: false, examDate: nil)])[0]
    }

    @Test("Announcements, materials and exam news count on their own buttons")
    func counts() {
        let items = [item(.announcementPosted, minutesAgo: 5, id: "a"), item(.announcementPosted, minutesAgo: 6, id: "b"),
                     item(.materialAdded, minutesAgo: 5, id: "c"), item(.solutionsPosted, minutesAgo: 5, id: "d"),
                     item(.roomChanged, minutesAgo: 5, id: "e"), item(.assignmentAdded, minutesAgo: 5, id: "f")]
        let badges = CourseHubBadges(items: items, seenAt: now.addingTimeInterval(-3600))
        #expect(badges.announcements == 2)
        #expect(badges.materials == 2)
        #expect(badges.exams == 1)
    }

    @Test("Items seen before the feed was last opened do not count")
    func seen() {
        let badges = CourseHubBadges(items: [item(.announcementPosted, minutesAgo: 120, id: "a")],
                                     seenAt: now.addingTimeInterval(-3600))
        #expect(badges.announcements == 0)
    }
}
