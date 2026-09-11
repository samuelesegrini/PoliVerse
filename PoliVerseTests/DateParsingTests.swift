import Testing
import Foundation
@testable import PoliVerse

@Suite("PoliMi timestamps")
struct DateParsingTests {
    /// The agenda sends wall-clock times with no zone. Parsing them as UTC
    /// "works" and is silently wrong by one or two hours depending on DST,
    /// which is exactly the kind of bug that reaches users.
    @Test("Naive timestamps are read as Europe/Rome, not UTC")
    func naiveTimestampsUseRome() throws {
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))

        // CET (+1)
        let winter = try #require(PoliMiDate.parse("2026-01-15T09:15:00"))
        #expect(rome.component(.hour, from: winter) == 9)
        #expect(rome.component(.minute, from: winter) == 15)

        // CEST (+2) — same wall-clock hour, different offset from UTC.
        let summer = try #require(PoliMiDate.parse("2026-07-15T09:15:00"))
        #expect(rome.component(.hour, from: summer) == 9)

        // The two must NOT land on the same UTC offset.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(utc.component(.hour, from: winter) == 8)
        #expect(utc.component(.hour, from: summer) == 7)
    }

    @Test("A real ISO8601 offset is still accepted")
    func isoWithOffsetParses() throws {
        let date = try #require(PoliMiDate.parse("2026-03-14T14:30:00Z"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(utc.component(.hour, from: date) == 14)
    }

    @Test("Date-only values parse, for all-day entries")
    func dateOnlyParses() throws {
        let date = try #require(PoliMiDate.parse("2026-05-02"))
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        #expect(rome.component(.day, from: date) == 2)
    }

    @Test("Garbage returns nil rather than a wrong date")
    func garbageFails() {
        #expect(PoliMiDate.parse("") == nil)
        #expect(PoliMiDate.parse("not a date") == nil)
    }

    /// Exam sittings split day and time across two fields.
    @Test("Exam time is grafted onto the exam day")
    func timeAppliedToDate() throws {
        let day = try #require(PoliMiDate.parse("2026-06-12"))
        let combined = try #require(PoliMiDate.applying(time: "14:30", to: day))
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        #expect(rome.component(.day, from: combined) == 12)
        #expect(rome.component(.hour, from: combined) == 14)
        #expect(rome.component(.minute, from: combined) == 30)
    }

    /// Building a Calendar by identifier defaults to a Sunday week start,
    /// which is wrong for an Italian timetable.
    @Test("The Rome calendar starts weeks on Monday")
    func weekStartsMonday() {
        #expect(PoliMiDate.romeCalendar.firstWeekday == 2)
    }
}

/// The agenda mixes lectures, exams, deadlines and notices in one feed, so the
/// calendar filters it — and the filter has to agree with the day dots, or the
/// strip promises days that turn out empty.
@Suite("Calendar filtering")
struct CalendarFilterTests {
    private func event(_ kind: EventKind) -> AgendaEvent {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return AgendaEvent(
            id: kind.rawValue, title: "x", start: start,
            end: start.addingTimeInterval(3600), kind: kind
        )
    }

    @Test("Everything matches the unfiltered view")
    func allMatches() {
        for kind in EventKind.allCases {
            #expect(CalendarView.Filter.all.matches(event(kind)))
        }
    }

    @Test("Lectures excludes anything that is not a lecture")
    func lecturesOnly() {
        #expect(CalendarView.Filter.lectures.matches(event(.lecture)))
        for kind in [EventKind.exam, .deadline, .news, .custom] {
            #expect(CalendarView.Filter.lectures.matches(event(kind)) == false)
        }
    }

    /// Exams belong with deadlines: both are things with a date to prepare for.
    @Test("Deadlines covers exams too")
    func deadlinesIncludeExams() {
        #expect(CalendarView.Filter.deadlines.matches(event(.deadline)))
        #expect(CalendarView.Filter.deadlines.matches(event(.exam)))
        #expect(CalendarView.Filter.deadlines.matches(event(.lecture)) == false)
    }
}
