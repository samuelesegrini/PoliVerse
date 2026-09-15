import Foundation
import Testing
@testable import PoliVerse

/// What each section of Oggi lists, chosen from the data the app already has.
@Suite("Today digest")
struct TodayDigestTests {
    private let calendar = PoliMiDate.romeCalendar
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 11))! }

    private func event(_ id: Int, _ from: Double, _ to: Double, _ kind: EventKind = .lecture) -> AgendaEvent {
        AgendaEvent(id: id, title: "E\(id)", start: now.addingTimeInterval(from * 3600),
                    end: now.addingTimeInterval(to * 3600), kind: kind, room: "Aula \(id)", roomAcronym: nil, calendarName: nil)
    }

    private func deadline(_ id: Int, _ hours: Double) -> AssignmentDeadline {
        AssignmentDeadline(id: id, courseCode: "C\(id)", courseName: "Corso \(id)", name: "Consegna \(id)",
                           due: now.addingTimeInterval(hours * 3600))
    }

    private func exam(_ id: Int, _ hours: Double?, _ status: ExamStatus = .enrolled) -> ExamSession {
        ExamSession(id: id, courseName: "Esame \(id)", courseCode: "X\(id)", teacher: nil,
                    date: hours.map { now.addingTimeInterval($0 * 3600) }, room: nil, enrolmentOpens: nil,
                    enrolmentCloses: nil, enrolledCount: nil, kind: nil, status: status)
    }

    @Test("The timetable is the shown day's lessons and exams, in order; deadlines and other days are left out")
    func timetable() {
        let events = [event(3, 3, 4), event(1, -2, -1), event(2, 1, 2, .exam), event(4, 1, 2, .deadline), event(5, 24, 25)]
        #expect(TodayDigest.timetable(events: events, day: now, calendar: calendar).map(\.id) == [1, 2, 3])
    }

    @Test("Deadlines still to come, soonest first, up to the limit")
    func deadlines() {
        let deadlines = [deadline(1, 48), deadline(2, -1), deadline(3, 5), deadline(4, 100)]
        #expect(TodayDigest.deadlines(deadlines, now: now, limit: 2).map(\.id) == [3, 1])
    }

    @Test("Exams with a date from today on, soonest first; graded and undated ones are left out")
    func exams() {
        let sessions = [exam(1, 72), exam(2, -2), exam(3, nil), exam(4, 24, .open), exam(5, 30, .graded(ExamGrade(value: 28, text: "28", passed: true, refusable: false))), exam(6, -30)]
        #expect(TodayDigest.exams(sessions, now: now, calendar: calendar, limit: 5).map(\.id) == [2, 4, 1])
    }

    @Test("In arrivo mixes exams, deadlines and exam dates in the agenda, soonest first, without lessons")
    func upcoming() {
        let items = TodayDigest.upcoming(
            events: [event(1, 1, 2), event(2, 26, 28, .exam), event(3, -5, -4, .exam)],
            deadlines: [deadline(10, 3), deadline(11, -3)],
            exams: [exam(20, 50)],
            now: now, limit: 5)
        #expect(items.map(\.id) == ["deadline-10", "event-2", "exam-20"])
        // Rows open what they stand for; a WeBeep deadline has no screen.
        #expect(items.map(\.opens?.id) == [nil, "event-2", "exam-20"])
        #expect(TodayDigest.upcoming(events: [], deadlines: [deadline(1, 1), deadline(2, 2)], exams: [], now: now, limit: 1).count == 1)
    }

    @Test("An exam in both the agenda and the career shows once, from the agenda")
    func upcomingWithoutDuplicates() {
        let agendaExam = AgendaEvent(id: 7, title: "Esame 20 - appello", start: now.addingTimeInterval(50 * 3600),
                                     end: now.addingTimeInterval(52 * 3600), kind: .exam, room: "Aula 7", roomAcronym: nil, calendarName: nil)
        let items = TodayDigest.upcoming(events: [agendaExam], deadlines: [], exams: [exam(20, 49), exam(21, 51)], now: now, limit: 5)
        #expect(items.map(\.id) == ["event-7", "exam-21"])
    }

    @Test("A lesson takes a course colour from its title: the same every day, one of the eight")
    func courseColour() {
        let first = TodayDigest.colourIndex(for: "Basi di Dati")
        #expect(first == TodayDigest.colourIndex(for: "Basi di Dati"))
        #expect((0..<8).contains(first))
        let spread = Set(["Basi di Dati", "Reti Logiche", "Analisi 2", "Fisica", "Ingegneria del Software", "Automatica"]
            .map(TodayDigest.colourIndex(for:)))
        #expect(spread.count >= 3)
    }

    @Test("The toggle for course colours exists only on the timetable, and is on for a new one")
    func courseColoursDefault() {
        #expect(TodaySection(kind: .timetable).courseColours)
        #expect(TodaySection.Kind.timetable.hasCourseColours)
        #expect(!TodaySection.Kind.upcoming.hasCourseColours)
    }
}
