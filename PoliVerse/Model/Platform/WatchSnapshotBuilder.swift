import Foundation

/// Narrows the app's models to the small value the Watch is sent.
///
/// Separate from ``WatchBridge``, which is the transport and knows nothing
/// about courses or sittings, and separate from the view that triggers it. The
/// choice of *what is worth a wrist* lives here, in one place, and is tested.
nonisolated enum WatchSnapshotBuilder {
    /// Builds the snapshot for a day.
    ///
    /// Lectures and exams only: a deadline is an instant with nowhere to be on
    /// a timeline of a day, and the agenda's news entries are not the
    /// student's own commitments.
    ///
    /// - Parameters:
    ///   - events: The agenda.
    ///   - exams: The sittings from the career.
    ///   - day: The day to describe.
    ///   - career: The career figures, when they have been written.
    ///   - calendar: The calendar the day is measured in.
    /// - Returns: The snapshot.
    static func build(events: [AgendaEvent], exams: [ExamSession], day: Date,
                      career: CareerSnapshot? = nil,
                      calendar: Calendar = PoliMiDate.romeCalendar) -> WatchSnapshot {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let entries = events
            .filter { $0.kind == .lecture || $0.kind == .exam }
            // Overlapping the day rather than starting in it, as the widgets
            // read it: a lecture already under way belongs to today.
            .filter { $0.start < end && $0.end >= start }
            .sorted { $0.start < $1.start }
            .map {
                WatchSnapshot.Entry(id: $0.id, title: $0.title, room: $0.roomLabel,
                                    start: $0.start, end: $0.end, isExam: $0.kind == .exam)
            }
        let next = exams
            .filter { ($0.date ?? .distantPast) >= day }
            .filter { if case .graded = $0.status { return false } else { return true } }
            .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        return WatchSnapshot(
            day: start,
            entries: entries,
            nextExamName: next?.courseName,
            nextExamDate: next?.date,
            // Zero is not "no results": an account with nothing recorded yet
            // should show nothing rather than a confident 0,00.
            mean: (career?.hasResults ?? false) ? career?.mean : nil,
            earnedCFU: career?.earnedCFU ?? 0,
            sentAt: .now)
    }
}
