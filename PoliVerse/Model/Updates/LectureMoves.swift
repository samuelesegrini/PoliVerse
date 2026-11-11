import Foundation

/// A lecture that is still ahead and now happens in another room or at another time.
nonisolated struct LectureMove: Equatable, Sendable {
    /// The entry's id in the agenda.
    let id: Int
    /// The lecture's name.
    let title: String
    /// When it was to begin.
    let oldStart: Date
    /// When it begins now.
    let newStart: Date
    /// Where it was to be, as the student is shown it.
    let oldRoom: String?
    /// Where it is now.
    let newRoom: String?

    /// Whether the time changed, rather than only the room.
    var timeChanged: Bool { oldStart != newStart }
}

/// Finds the lectures a refresh of the timetable moved.
///
/// Values in, moves out. Built on ``ChangeDetector``, so a lecture is matched by
/// the agenda's own id: one that keeps its id and changes room or start is a
/// move. A lecture that disappears and another that appears are not paired up,
/// because nothing says they are the same lecture, and telling a student that a
/// lecture moved when it did not is worse than saying nothing.
nonisolated enum LectureMoves {
    /// What of a lecture makes it a different appointment.
    private struct Facts: Identifiable, Equatable {
        let id: Int
        let start: Date
        let room: String?
    }

    /// The lectures still ahead that changed room or start.
    ///
    /// - Parameters:
    ///   - old: The stored copy of a week.
    ///   - new: The week as just fetched.
    ///   - now: The current moment. A lecture that has begun is history.
    /// - Returns: The moves, soonest first.
    static func moves(from old: [AgendaEvent], to new: [AgendaEvent], now: Date) -> [LectureMove] {
        let before = old.filter { $0.kind == .lecture }
        let after = new.filter { $0.kind == .lecture }
        let changed = ChangeDetector.changes(from: before.map(facts), to: after.map(facts)).changed
        guard !changed.isEmpty else { return [] }
        let was = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return after.compactMap { event -> LectureMove? in
            guard changed.contains(String(event.id)), let previous = was[event.id], event.start > now else { return nil }
            return LectureMove(id: event.id, title: event.title, oldStart: previous.start, newStart: event.start,
                               oldRoom: previous.roomLabel, newRoom: event.roomLabel)
        }
        .sorted { $0.newStart < $1.newStart }
    }

    private static func facts(_ event: AgendaEvent) -> Facts {
        Facts(id: event.id, start: event.start, room: event.roomLabel)
    }

    /// The update the feed records for a move.
    ///
    /// - Parameters:
    ///   - move: The move.
    ///   - now: When it was noticed.
    static func update(for move: LectureMove, now: Date) -> ExamUpdate {
        ExamUpdate(
            kind: .lectureMoved, examID: nil, courseCode: move.title, courseName: move.title,
            detectedAt: now, source: .agenda,
            evidence: "agenda:/events event_id=\(move.id) \(move.timeChanged ? "date_start" : "room")",
            oldValue: describe(start: move.oldStart, room: move.oldRoom, withTime: move.timeChanged),
            newValue: describe(start: move.newStart, room: move.newRoom, withTime: move.timeChanged),
            // The same lecture can move twice: each place it lands is its own news.
            identity: "\(move.id)|\(Int(move.newStart.timeIntervalSince1970))|\(move.newRoom ?? "-")",
            wasEnrolled: true, examDate: move.newStart)
    }

    /// A lecture's place and, when the time is what changed, its time.
    private static func describe(start: Date, room: String?, withTime: Bool) -> String {
        guard withTime else { return room ?? String(localized: "aula da definire") }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style = style.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = PoliMiDate.romeCalendar.timeZone
        return [start.formatted(style), room].compactMap { $0 }.joined(separator: " · ")
    }
}
