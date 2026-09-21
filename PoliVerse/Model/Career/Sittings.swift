import Foundation

/// The student's exam sittings, and the questions the screens ask of them.
///
/// A value type beside ``StudyPlan``, and for the same reason: this is
/// arithmetic over data already in hand, so it needs no session, no network and
/// no actor to answer — which means it can be tested directly rather than
/// through whatever happened to load it.
///
/// `now` is a parameter throughout rather than `Date.now` read inside. Every
/// question here is "what is still ahead", which is only answerable relative to
/// a moment, and a moment read internally is a test that passes until the clock
/// disagrees.
nonisolated struct Sittings: Sendable, Equatable {
    let all: [ExamSession]

    init(_ all: [ExamSession] = []) {
        self.all = all
    }

    /// Sittings still ahead, soonest first.
    ///
    /// By day rather than by instant: a sitting this morning is still today's
    /// exam at two in the afternoon, and dropping it at the moment it started
    /// takes it off the screen of the student walking into it.
    func upcoming(now: Date = .now, calendar: Calendar = .current) -> [ExamSession] {
        let today = calendar.startOfDay(for: now)
        return all
            .filter { $0.grade == nil && ($0.date ?? .distantPast) >= today }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Sittings the student is signed up for.
    func enrolled(now: Date = .now, calendar: Calendar = .current) -> [ExamSession] {
        upcoming(now: now, calendar: calendar).filter { $0.status == .enrolled }
    }

    /// The sitting an update is about, while it is still listed.
    func sitting(for update: ExamUpdate) -> ExamSession? {
        guard let id = update.examID else { return nil }
        return all.first { $0.id == id }
    }

    /// The soonest sitting strictly after `now`, for the widget's one line.
    ///
    /// Strictly after, unlike ``upcoming(now:calendar:)``: a widget saying
    /// "next exam" about one that started this morning would be wrong in a way
    /// a full list is not.
    func next(after now: Date = .now) -> ExamSession? {
        all
            .filter { $0.grade == nil && ($0.date ?? .distantPast) > now }
            .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}
