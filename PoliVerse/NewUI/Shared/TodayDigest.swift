import Foundation

/// What each Oggi section lists, picked from data the app already loads:
/// the agenda, WeBeep's deadlines and the exam sittings.
nonisolated enum TodayDigest {
    /// One line of In arrivo, whichever source it came from.
    nonisolated struct Item: Identifiable, Equatable, Sendable {
        nonisolated enum Source: Sendable { case exam, deadline }

        let id: String
        let title: String
        let detail: String?
        let date: Date
        let source: Source
    }

    /// One of the eight course colours for a lesson, from its title with the
    /// same hash courses use, so a lesson keeps its colour from day to day.
    static func colourIndex(for title: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in title.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return Int(hash % 8)
    }

    /// The day's lessons and exams, by start time.
    static func timetable(events: [AgendaEvent], day: Date, calendar: Calendar = PoliMiDate.romeCalendar) -> [AgendaEvent] {
        events
            .filter { ($0.kind == .lecture || $0.kind == .exam) && calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// Assignments still to hand in, soonest first.
    static func deadlines(_ deadlines: [AssignmentDeadline], now: Date, limit: Int) -> [AssignmentDeadline] {
        Array(deadlines.filter { $0.due >= now }.sorted { $0.due < $1.due }.prefix(limit))
    }

    /// Sittings with a date from the start of today, not yet graded.
    static func exams(_ sessions: [ExamSession], now: Date, calendar: Calendar = PoliMiDate.romeCalendar, limit: Int) -> [ExamSession] {
        let ahead = sessions.filter { isAhead($0, from: calendar.startOfDay(for: now)) }
        return Array(ahead.sorted { ($0.date ?? now) < ($1.date ?? now) }.prefix(limit))
    }

    private static func isAhead(_ session: ExamSession, from start: Date) -> Bool {
        guard let date = session.date, date >= start else { return false }
        if case .graded = session.status { return false }
        return true
    }

    /// Exams and deadlines still ahead, from every source, soonest first. A
    /// sitting the agenda already lists that day, under a title naming the
    /// course, is left to the agenda.
    static func upcoming(events: [AgendaEvent], deadlines: [AssignmentDeadline], exams: [ExamSession],
                         now: Date, calendar: Calendar = PoliMiDate.romeCalendar, limit: Int) -> [Item] {
        let agendaExams = events.filter { $0.kind == .exam }
        let fromAgenda = events
            .filter { ($0.kind == .exam || $0.kind == .deadline) && $0.start >= now }
            .map { Item(id: "event-\($0.id)", title: $0.title, detail: $0.room ?? $0.roomAcronym, date: $0.start,
                        source: $0.kind == .exam ? .exam : .deadline) }
        let fromWeBeep = deadlines
            .filter { $0.due >= now }
            .map { Item(id: "deadline-\($0.id)", title: $0.name, detail: $0.courseName, date: $0.due, source: .deadline) }
        let fromCareer = exams
            .filter { isAhead($0, from: now) }
            .filter { session in
                !agendaExams.contains { event in
                    calendar.isDate(event.start, inSameDayAs: session.date ?? now)
                        && event.title.localizedCaseInsensitiveContains(session.courseName)
                }
            }
            .map { Item(id: "exam-\($0.id)", title: $0.courseName, detail: $0.room, date: $0.date ?? now, source: .exam) }
        return Array((fromAgenda + fromWeBeep + fromCareer).sorted { $0.date < $1.date }.prefix(limit))
    }
}
