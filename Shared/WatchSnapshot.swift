import Foundation

/// What the Watch shows, in one small value the phone sends it.
///
/// The Watch is not a second copy of the app. It has no session, no token and
/// no reach into the university's services — WatchConnectivity carries a
/// dictionary between two processes on two devices, and that is the whole
/// channel. So the phone decides what is worth knowing on a wrist and sends
/// exactly that: today's lectures, the next exam, and where the career stands.
///
/// Kept deliberately small for the same reason ``CareerSnapshot`` is: the
/// transfer is a dictionary, the queue is finite, and a payload that carried
/// the whole agenda would spend its budget on days nobody is looking at.
nonisolated struct WatchSnapshot: Codable, Sendable, Equatable {
    /// One entry, flattened to what a wrist can read at a glance.
    nonisolated struct Entry: Codable, Sendable, Equatable, Identifiable {
        /// The entry's identity, from ``AgendaEvent/id``.
        var id: Int
        /// What it is called.
        var title: String
        /// Where it is, when known.
        var room: String?
        /// When it begins.
        var start: Date
        /// When it ends.
        var end: Date
        /// Whether it is an exam rather than a lecture.
        var isExam: Bool
    }

    /// The day these entries belong to, so the Watch can say "oggi" only when
    /// it means today.
    var day: Date
    /// The day's lectures and exams, in order.
    var entries: [Entry]
    /// The teaching of the soonest sitting ahead, or `nil` when there is none.
    var nextExamName: String?
    /// When that sitting is.
    var nextExamDate: Date?
    /// The weighted average so far, or `nil` when nothing is recorded yet.
    var mean: Double?
    /// Credits earned.
    var earnedCFU: Int
    /// When the phone built this.
    var sentAt: Date

    /// The record name the snapshot is stored under on the Watch.
    ///
    /// The Watch keeps the last one it received in its own container — not the
    /// app group, which does not cross devices — so a wrist raised out of
    /// range shows the last thing known rather than an empty screen.
    static let cacheName = "watch-snapshot"

    /// The key the payload travels under in the WatchConnectivity dictionary.
    static let payloadKey = "snapshot"

    /// Whether the entries describe the day containing a date.
    ///
    /// - Parameters:
    ///   - date: Usually the moment the Watch is drawing.
    ///   - calendar: The calendar to judge in.
    /// - Returns: `true` when the snapshot is about that day.
    func covers(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }

    /// The entry under way at a moment, or the next one to come.
    ///
    /// - Parameter date: The moment to judge at.
    /// - Returns: The entry, or `nil` when the day has nothing left.
    func current(at date: Date) -> Entry? {
        entries.first { $0.start <= date && date < $0.end }
            ?? entries.filter { $0.start > date }.min { $0.start < $1.start }
    }
}
