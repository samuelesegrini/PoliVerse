import Foundation

/// The student's exam sittings, and the questions the screens ask of them.
///
/// A value type, like ``StudyPlan``: arithmetic over data already in hand, needing
/// no session, no network and no actor to answer.
///
/// `now` is a parameter throughout rather than read inside. Every question here is
/// about what is still ahead, which is only answerable relative to a moment.
nonisolated struct Sittings: Sendable, Equatable {
    /// Every sitting known.
    let all: [ExamSession]

    /// Wraps a set of sittings.
    ///
    /// - Parameter all: The sittings to answer about.
    init(_ all: [ExamSession] = []) {
        self.all = all
    }

    /// Unmarked sittings still ahead, soonest first.
    ///
    /// Counted by day rather than by instant: a sitting this morning is still today's
    /// exam in the afternoon, and dropping it the moment it starts takes it off the
    /// screen of the student walking into it.
    ///
    /// - Parameters:
    ///   - now: The moment to measure from.
    ///   - calendar: The calendar the day boundary is taken in.
    /// - Returns: The sittings, soonest first. Ones without a date sort last.
    func upcoming(now: Date = .now, calendar: Calendar = .current) -> [ExamSession] {
        let today = calendar.startOfDay(for: now)
        return all
            .filter { $0.grade == nil && ($0.date ?? .distantPast) >= today }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Upcoming sittings the student is signed up for.
    ///
    /// - Parameters:
    ///   - now: The moment to measure from.
    ///   - calendar: The calendar the day boundary is taken in.
    /// - Returns: The enrolled sittings, soonest first.
    func enrolled(now: Date = .now, calendar: Calendar = .current) -> [ExamSession] {
        upcoming(now: now, calendar: calendar).filter { $0.status == .enrolled }
    }

    /// The sitting an update is about, while it is still listed.
    ///
    /// - Parameter update: The update to resolve.
    /// - Returns: The sitting, or `nil` when the update names none or it is no longer
    ///   listed.
    func sitting(for update: ExamUpdate) -> ExamSession? {
        guard let id = update.examID else { return nil }
        return all.first { $0.id == id }
    }

    /// The soonest unmarked sitting strictly after a moment, for the widget's one line.
    ///
    /// Strictly after, unlike ``upcoming(now:calendar:)``: a widget naming a “next exam”
    /// that started this morning would be wrong in a way a full list is not.
    ///
    /// - Parameter now: The moment to measure from.
    /// - Returns: The sitting, or `nil` when none is ahead.
    func next(after now: Date = .now) -> ExamSession? {
        all
            .filter { $0.grade == nil && ($0.date ?? .distantPast) > now }
            .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}
