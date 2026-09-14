import Foundation
import Testing
@testable import PoliVerse

/// Two ways a student turns the feed down: silencing a course, and having
/// already seen what is there.
@Suite("Muted courses and unread updates")
struct FeedAttentionTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func update(_ kind: ExamUpdate.Kind, course: String = "097785", hoursAgo: Double = 0,
                        exam: Int? = 1) -> ExamUpdate {
        ExamUpdate(kind: kind, examID: exam, courseCode: course, courseName: "Basi di Dati",
                   detectedAt: now.addingTimeInterval(-hoursAgo * 3600), source: .exams,
                   evidence: "t", newValue: "27", wasEnrolled: true, examDate: nil)
    }

    /// §11.3: a silenced course stays in the app, whatever the news.
    @Test("A muted course's updates stay in the app, even a published mark")
    func muted() {
        var preferences = NotificationPreferences()
        preferences.setMuted(true, code: "097785", name: "Basi di Dati")
        let other = ExamUpdate(kind: .gradePublished, examID: 2, courseCode: "083801", courseName: "Chimica",
                               detectedAt: now, source: .exams, evidence: "t", newValue: "27",
                               wasEnrolled: true, examDate: nil)
        let decided = ExamUpdatePolicy.decide(
            [update(.gradePublished), other],
            history: [], preferences: preferences, now: now)
        #expect(decided.map(\.delivery) == [.inApp, .urgent])
    }

    @Test("Muted courses survive a round trip, and older stored preferences have none")
    func mutedStored() throws {
        var preferences = NotificationPreferences()
        preferences.setMuted(true, code: "097785", name: "Basi di Dati")
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(NotificationPreferences.self, from: data).mutedCourses
                    == [MutedCourse(code: "097785", name: "Basi di Dati")])
        let legacy = Data(#"{"lectures":true,"examUpdates":true}"#.utf8)
        #expect(try JSONDecoder().decode(NotificationPreferences.self, from: legacy).mutedCourses.isEmpty)
    }

    @Test("Unread counts facts seen after the last visit, not sightings")
    func unread() {
        let items = FeedItem.items(from: [
            update(.gradePublished, hoursAgo: 1), update(.refusalOpened, hoursAgo: 1),   // one fact
            update(.roomChanged, hoursAgo: 5, exam: 2),
            update(.discovered, hoursAgo: 30, exam: 3),
        ])
        #expect(FeedItem.unreadCount(items, seenAt: now.addingTimeInterval(-10 * 3600)) == 2)
        #expect(FeedItem.unreadCount(items, seenAt: nil) == 3)
        #expect(FeedItem.unreadCount(items, seenAt: now) == 0)
    }

    @Test("A superseded mark is not unread")
    func supersededNotUnread() {
        var file = ExamUpdate(kind: .resultsPosted, examID: nil, courseCode: "097785", courseName: "Basi di Dati",
                              detectedAt: now.addingTimeInterval(-7200), source: .webeep, evidence: "t",
                              newValue: "Esiti.pdf", wasEnrolled: true, examDate: nil)
        file.lookup = ResultsLookup(looksLikeResults: true, found: true, grade: "27")
        let items = FeedItem.items(from: [update(.gradePublished, hoursAgo: 1), file])
        #expect(FeedItem.unreadCount(items, seenAt: nil) == 1)
    }

    /// §3: the same teaching has a different code on WeBeep.
    @Test("Muting from a WeBeep row also mutes the course's exam news, matched by name")
    func acrossSources() {
        var preferences = NotificationPreferences()
        preferences.setMuted(true, code: "moodle-4123", name: "BASI DI DATI")
        #expect(preferences.isMuted(code: "097785", name: "Basi di Dati"))
        #expect(!preferences.isMuted(code: "083801", name: "Chimica"))
        preferences.setMuted(false, code: "097785", name: "Basi di Dati")
        #expect(preferences.mutedCourses.isEmpty)
    }

    @Test("A muted course gets no exam, enrolment or assignment reminders, and no summary")
    func remindersMuted() {
        var preferences = NotificationPreferences()
        preferences.setMuted(true, code: "097785", name: "Basi di Dati")
        let sitting = ExamSession(id: 1, courseName: "Basi di Dati", courseCode: "097785", teacher: nil,
                                  date: now.addingTimeInterval(3 * 86400), room: nil,
                                  enrolmentOpens: nil, enrolmentCloses: now.addingTimeInterval(2 * 86400),
                                  enrolledCount: nil, kind: nil, status: .open)
        let deadline = AssignmentDeadline(id: 1, courseCode: "moodle-4123", courseName: "Basi di Dati",
                                          name: "Progetto", due: now.addingTimeInterval(3 * 86400))
        var held = update(.enrolmentOpened)
        held.delivery = .digest
        let plan = NotificationPlan.build(events: [], exams: [sitting], assignments: [deadline], updates: [held],
                                          preferences: preferences, now: now)
        #expect(plan.isEmpty)
    }

    @Test("When the feed was last seen is kept with the account's log")
    @MainActor
    func seenPersists() async {
        let offline = OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
        let fixed = now
        let feed = UpdateFeed(offline: offline, clock: { fixed })
        feed.show(account: "1")
        feed.markSeen()
        let reopened = UpdateFeed(offline: offline, clock: { fixed })
        reopened.show(account: "1")
        #expect(reopened.seenAt == fixed)
        reopened.show(account: "2")
        #expect(reopened.seenAt == nil)
    }
}
