import Foundation

/// Narrows the app's models to the small value the Watch is sent.
///
/// Separate from ``WatchBridge``, which is the transport and knows nothing
/// about courses or sittings, and separate from the view that triggers it. The
/// choice of *what is worth a wrist* lives here, in one place, and is tested.
nonisolated enum WatchSnapshotBuilder {
    /// Builds the snapshot for the days starting at one.
    ///
    /// Lectures and exams only: a deadline is an instant with nowhere to be on
    /// a timeline of a day, and the agenda's news entries are not the
    /// student's own commitments.
    ///
    /// - Parameters:
    ///   - events: The agenda.
    ///   - exams: The sittings from the career.
    ///   - day: The first day to describe; ``WatchSnapshot/horizonDays`` are
    ///     sent from it.
    ///   - career: The career figures, when they have been written.
    ///   - calendar: The calendar the day is measured in.
    /// - Returns: The snapshot.
    static func build(events: [AgendaEvent], exams: [ExamSession], day: Date,
                      career: CareerSnapshot? = nil,
                      calendar: Calendar = PoliMiDate.romeCalendar) -> WatchSnapshot {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: WatchSnapshot.horizonDays, to: start) ?? start
        let entries = events
            .filter { $0.kind == .lecture || $0.kind == .exam }
            // Overlapping the days rather than starting in them, as the
            // widgets read it: a lecture already under way belongs to today.
            .filter { $0.start < end && $0.end >= start }
            .sorted { $0.start < $1.start }
            .map {
                WatchSnapshot.Entry(id: $0.id, title: $0.title, room: $0.roomLabel,
                                    start: $0.start, end: $0.end, isExam: $0.kind == .exam)
            }
        let sittings: [WatchSnapshot.Exam] = exams
            .filter { if case .graded = $0.status { false } else { true } }
            .compactMap { session in
                guard let date = session.date, date >= start else { return nil }
                let enrolled = if case .enrolled = session.status { true } else { false }
                return WatchSnapshot.Exam(id: session.id, name: session.courseName, date: date,
                                          isEnrolled: enrolled)
            }
            .sorted { $0.date < $1.date }
            .prefix(WatchSnapshot.examLimit)
            .map(\.self)
        return WatchSnapshot(
            day: start,
            entries: entries,
            exams: sittings,
            // Zero is not "no results": an account with nothing recorded yet
            // should show nothing rather than a confident 0,00.
            mean: (career?.hasResults ?? false) ? career?.mean : nil,
            earnedCFU: career?.earnedCFU ?? 0,
            plannedCFU: career?.plannedCFU ?? 0,
            sentAt: .now)
    }
}
