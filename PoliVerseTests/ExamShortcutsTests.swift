import Foundation
import Testing
@testable import PoliVerse

/// What leaves the app on the student's request: a calendar event for a
/// sitting, and a spoken summary of what changed.
@Suite("Exam calendar event and spoken summary")
struct ExamShortcutsTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func sitting(date: Date?, room: String? = "B.3.2") -> ExamSession {
        ExamSession(id: 7, courseName: "Basi di Dati", courseCode: "097785", teacher: "Stefano Ceri",
                    date: date, room: room, enrolmentOpens: nil, enrolmentCloses: nil,
                    enrolledCount: nil, kind: "Scritto", status: .enrolled)
    }

    @Test("A sitting becomes an event with its room, a sensible length and where the facts came from")
    func calendarEvent() throws {
        let start = now.addingTimeInterval(5 * 86400)
        let event = try #require(ExamCalendarEvent(sitting: sitting(date: start)))
        #expect(event.title == "Basi di Dati · Scritto")
        #expect(event.start == start)
        #expect(event.end == start.addingTimeInterval(ExamCalendarEvent.defaultLength))
        #expect(event.location == "B.3.2")
        #expect(event.notes.contains("Stefano Ceri"))
        #expect(event.notes.contains("Servizi Online"))
    }

    @Test("A sitting with no date has nothing to put in a calendar")
    func noDate() {
        #expect(ExamCalendarEvent(sitting: sitting(date: nil)) == nil)
    }

    /// A date without a time arrives at midnight; a three-hour exam starting
    /// at 00:00 would be wrong in a way the student notices.
    @Test("A sitting at midnight is an all-day event")
    func allDay() throws {
        let midnight = PoliMiDate.romeCalendar.startOfDay(for: now)
        let event = try #require(ExamCalendarEvent(sitting: sitting(date: midnight, room: nil)))
        #expect(event.isAllDay)
        #expect(event.end == event.start)
        #expect(event.location == nil)
    }

    private func update(_ kind: ExamUpdate.Kind, hoursAgo: Double, course: String = "Basi di Dati",
                        exam: Int? = 1) -> ExamUpdate {
        ExamUpdate(kind: kind, examID: exam, courseCode: course, courseName: course,
                   detectedAt: now.addingTimeInterval(-hoursAgo * 3600), source: .exams,
                   evidence: "t", wasEnrolled: true, examDate: nil)
    }

    @Test("The spoken summary counts the week's facts and names the first few")
    func summary() {
        let updates = [
            update(.gradePublished, hoursAgo: 2), update(.refusalOpened, hoursAgo: 2),
            update(.roomChanged, hoursAgo: 20, course: "Fisica", exam: 2),
            update(.announcementPosted, hoursAgo: 30, course: "Chimica", exam: nil),
            update(.materialAdded, hoursAgo: 40, course: "Analisi", exam: nil),
            update(.discovered, hoursAgo: 24 * 9, course: "Vecchio", exam: 9),
        ]
        let text = ExamUpdatesSummary.spoken(updates, now: now)
        // Three facts in the week: the refusal folds into its mark, new
        // material is not worth saying out loud, the nine-day-old one is out.
        #expect(text.hasPrefix(String(localized: "3 novità sui tuoi esami questa settimana.")))
        #expect(text.contains("Basi di Dati"))
        #expect(text.contains("Fisica"))
        #expect(text.contains("Chimica"))
        #expect(!text.contains("Analisi"))
        #expect(!text.contains("Vecchio"))
    }

    @Test("No news is said as such")
    func nothing() {
        #expect(ExamUpdatesSummary.spoken([], now: now) == String(localized: "Nessuna novità sui tuoi esami questa settimana."))
    }

    @Test("A file's mark already confirmed officially is not spoken as news")
    func supersededNotSpoken() {
        var file = ExamUpdate(kind: .resultsPosted, examID: nil, courseCode: "F1", courseName: "Fisica",
                              detectedAt: now.addingTimeInterval(-5 * 3600), source: .webeep, evidence: "t",
                              newValue: "Esiti.pdf", wasEnrolled: true, examDate: nil)
        file.lookup = ResultsLookup(looksLikeResults: true, found: true, grade: "27")
        let official = ExamUpdate(kind: .gradePublished, examID: 1, courseCode: "F1", courseName: "Fisica",
                                  detectedAt: now.addingTimeInterval(-3600), source: .exams, evidence: "t",
                                  newValue: "27", wasEnrolled: true, examDate: nil)
        let text = ExamUpdatesSummary.spoken([official, file], now: now)
        #expect(text.hasPrefix(String(localized: "1 novità sui tuoi esami questa settimana.")))
        #expect(!text.contains("27"))
    }

    @Test("The next exam is said with its day and time, or its absence")
    func nextExam() {
        let it = Locale(identifier: "it_IT")
        let date = PoliMiDate.time(9, on: now.addingTimeInterval(3 * 86400))
        let snapshot = CareerSnapshot(mean: 27, earnedCFU: 100, plannedCFU: 180, examsGiven: 10,
                                      examsPlanned: 20, nextExamName: "Basi di Dati", nextExamDate: date)
        let text = NextExamSummary.spoken(snapshot, now: now, locale: it)
        #expect(text.contains("Basi di Dati"))
        #expect(text.contains("9:00"))
        #expect(NextExamSummary.spoken(nil, now: now) == String(localized: "Non risultano appelli in programma."))
        var past = snapshot
        past.nextExamDate = now.addingTimeInterval(-60)
        #expect(NextExamSummary.spoken(past, now: now) == String(localized: "Non risultano appelli in programma."))
    }
}
