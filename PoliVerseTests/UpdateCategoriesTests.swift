import Foundation
import Testing
@testable import PoliVerse

/// §13: which kinds of news notify, when the summary comes, and a course's
/// own news on its page.
@Suite("Update categories, summary time and course news")
struct UpdateCategoriesTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func update(_ kind: ExamUpdate.Kind, course: String = "097785", name: String = "Basi di Dati",
                        source: ExamUpdate.Source = .exams, hoursAgo: Double = 0) -> ExamUpdate {
        ExamUpdate(kind: kind, examID: 1, courseCode: course, courseName: name,
                   detectedAt: now.addingTimeInterval(-hoursAgo * 3600), source: source, evidence: "t",
                   newValue: "x", wasEnrolled: true, examDate: now.addingTimeInterval(4 * 86400))
    }

    @Test("Every kind belongs to exactly one category")
    func mapping() {
        for kind in ExamUpdate.Kind.allCases {
            #expect(UpdateCategory.allCases.filter { $0.kinds.contains(kind) }.count == 1, "\(kind)")
        }
        #expect(ExamUpdate.Kind.gradePublished.category == .results)
        #expect(ExamUpdate.Kind.roomChanged.category == .roomsAndDates)
        #expect(ExamUpdate.Kind.announcementPosted.category == .teachers)
        #expect(ExamUpdate.Kind.assignmentAdded.category == .coursework)
    }

    @Test("A category switched off keeps its news in the app")
    func categoryOff() {
        var preferences = NotificationPreferences()
        preferences.setCategory(.roomsAndDates, enabled: false)
        let decided = ExamUpdatePolicy.decide([update(.roomChanged), update(.gradePublished)],
                                              history: [], preferences: preferences, now: now)
        #expect(decided.map(\.delivery) == [.inApp, .urgent])
        #expect(!preferences.isEnabled(.roomsAndDates))
        preferences.setCategory(.roomsAndDates, enabled: true)
        #expect(preferences.isEnabled(.roomsAndDates))
    }

    @Test("The summary goes out at the student's chosen hour")
    func summaryHour() {
        var preferences = NotificationPreferences()
        preferences.digestHour = 20
        var held = update(.enrolmentOpened)
        held.delivery = .digest
        let digests = ExamUpdatePolicy.digests(from: [held], now: now, preferences: preferences)
        #expect(digests.first?.fireDate == PoliMiDate.time(20, on: now))
    }

    @Test("Older stored preferences have every category on and the summary at 18:00")
    func legacy() throws {
        let decoded = try JSONDecoder().decode(NotificationPreferences.self, from: Data(#"{"lectures":true}"#.utf8))
        #expect(UpdateCategory.allCases.allSatisfy(decoded.isEnabled))
        #expect(decoded.digestHour == 18)
    }

    /// The same teaching arrives with a WeBeep code and an exam-services code.
    @Test("A course's own news is found by code or by name")
    func courseNews() {
        let course = Course(id: "097785", name: "Basi di Dati", teacher: "—", cfu: 8, semester: "2",
                            academicYear: "2025-26")
        let updates = [
            update(.roomChanged),
            update(.announcementPosted, course: "moodle-4123", name: "BASI DI DATI", source: .webeep, hoursAgo: 1),
            update(.gradePublished, course: "083801", name: "Chimica", hoursAgo: 2),
        ]
        #expect(FeedItem.items(from: updates, for: course).count == 2)
    }

    @Test("Switching a kind off also cancels its queued summary")
    func queuedSummary() {
        var preferences = NotificationPreferences()
        var held = update(.enrolmentOpened)
        held.delivery = .digest
        #expect(!NotificationPlan.build(events: [], exams: [], updates: [held], preferences: preferences, now: now).isEmpty)
        preferences.setCategory(.enrolments, enabled: false)
        #expect(NotificationPlan.build(events: [], exams: [], updates: [held], preferences: preferences, now: now).isEmpty)
    }

    /// "Fisica" in two schools: both have real codes, so the name alone does
    /// not join them.
    @Test("Two coded teachings with the same name stay apart")
    func sameNameDifferentCourse() {
        let course = Course(id: "097785", name: "Basi di Dati", teacher: "—", cfu: 8, semester: "2",
                            academicYear: "2025-26")
        let other = update(.gradePublished, course: "054321", name: "Basi di Dati")
        #expect(FeedItem.items(from: [other], for: course).isEmpty)
    }
}
