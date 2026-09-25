import Foundation

/// What the Watch shows, in one small value the phone sends it.
///
/// The Watch is not a second copy of the app. It has no session, no token and
/// no reach into the university's services — WatchConnectivity carries a
/// dictionary between two processes on two devices, and that is the whole
/// channel. So the phone decides what is worth knowing on a wrist and sends
/// exactly that: the next few days of lectures, the sittings ahead, and where
/// the career stands.
///
/// A few days rather than one, because the Watch's complications draw a
/// timeline on their own long after the phone last spoke: a snapshot of today
/// alone leaves every face blank from midnight until the phone next runs.
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

        /// Whether it is under way at a moment.
        ///
        /// - Parameter date: The moment.
        /// - Returns: `true` between the start, included, and the end.
        func isOn(at date: Date) -> Bool { start <= date && date < end }
    }

    /// One sitting ahead.
    nonisolated struct Exam: Codable, Sendable, Equatable, Identifiable {
        /// The sitting's identity, from ``ExamSession/id``.
        var id: Int
        /// The teaching it examines.
        var name: String
        /// When it is.
        var date: Date
        /// Whether the student is enrolled in it, rather than only able to be.
        var isEnrolled: Bool
    }

    /// The first day the entries belong to, so the Watch can say "oggi" only
    /// when it means today.
    var day: Date
    /// The lectures and exams from ``day`` for ``horizonDays`` days, in order.
    var entries: [Entry]
    /// The next dated, ungraded sittings, soonest first, at most
    /// ``examLimit``.
    var exams: [Exam]
    /// The weighted average so far, or `nil` when nothing is recorded yet.
    var mean: Double?
    /// Credits earned.
    var earnedCFU: Int
    /// Credits in the study plan, or `0` when not known.
    var plannedCFU: Int
    /// When the phone built this.
    var sentAt: Date

    /// How many days of entries the phone sends.
    static let horizonDays = 3

    /// How many sittings the phone sends.
    static let examLimit = 3

    /// The record name the snapshot is stored under on the Watch.
    ///
    /// The Watch keeps the last one it received — in its own app group, which
    /// its complications share, not the phone's, which does not cross devices
    /// — so a wrist raised out of range shows the last thing known rather than
    /// an empty screen.
    static let cacheName = "watch-snapshot"

    /// The key the payload travels under in the WatchConnectivity dictionary.
    static let payloadKey = "snapshot"

    /// The key of the message the Watch sends to ask for a fresh snapshot.
    static let requestKey = "request"

    /// How old a snapshot can be before the Watch asks for a newer one when
    /// it comes to the front.
    ///
    /// Long enough that raising a wrist every few minutes does not wake the
    /// phone every time, short enough that a lecture moved this morning is
    /// right by the next glance.
    static let staleAfter: TimeInterval = 30 * 60

    /// Creates a snapshot.
    init(day: Date, entries: [Entry], exams: [Exam] = [], mean: Double? = nil,
         earnedCFU: Int = 0, plannedCFU: Int = 0, sentAt: Date = .now) {
        self.day = day
        self.entries = entries
        self.exams = exams
        self.mean = mean
        self.earnedCFU = earnedCFU
        self.plannedCFU = plannedCFU
        self.sentAt = sentAt
    }

    /// Decodes a snapshot, tolerating one from a build that sent fewer fields.
    ///
    /// A Watch updated before the phone would otherwise throw away the day it
    /// already has and show "nessun dato" until the phone next runs.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(Date.self, forKey: .day)
        entries = try container.decode([Entry].self, forKey: .entries)
        exams = try container.decodeIfPresent([Exam].self, forKey: .exams) ?? []
        mean = try container.decodeIfPresent(Double.self, forKey: .mean)
        earnedCFU = try container.decodeIfPresent(Int.self, forKey: .earnedCFU) ?? 0
        plannedCFU = try container.decodeIfPresent(Int.self, forKey: .plannedCFU) ?? 0
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt) ?? day
    }

    /// Whether the Watch should ask the phone for a newer snapshot.
    ///
    /// - Parameter date: The moment the Watch is judging at.
    /// - Returns: `true` when the snapshot is older than ``staleAfter`` or
    ///   no longer covers the day.
    func needsRefresh(at date: Date) -> Bool {
        !covers(date) || date.timeIntervalSince(sentAt) > Self.staleAfter
    }

    /// The soonest sitting ahead, if any.
    var nextExam: Exam? { exams.first }

    /// Whether the entries describe the day containing a date.
    ///
    /// - Parameters:
    ///   - date: Usually the moment the Watch is drawing.
    ///   - calendar: The calendar to judge in.
    /// - Returns: `true` when that day falls inside the snapshot's days.
    func covers(_ date: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: Self.horizonDays, to: start) else {
            return calendar.isDate(day, inSameDayAs: date)
        }
        return start <= date && date < end
    }

    /// The entries overlapping the day containing a date.
    ///
    /// - Parameters:
    ///   - date: Any moment of the day.
    ///   - calendar: The calendar the day is measured in.
    /// - Returns: The entries, in order.
    func entries(on date: Date, calendar: Calendar = .current) -> [Entry] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return entries.filter { $0.start < end && $0.end > start }
    }

    /// The days that have entries, from the one containing a date on.
    ///
    /// - Parameters:
    ///   - date: The moment to start from; days before it are left out.
    ///   - calendar: The calendar days are measured in.
    /// - Returns: The start of each day with its entries still to finish.
    func days(from date: Date, calendar: Calendar = .current) -> [(day: Date, entries: [Entry])] {
        let upcoming = entries.filter { $0.end > date }
        let starts = Set(upcoming.map { calendar.startOfDay(for: max($0.start, date)) })
        return starts.sorted().map { day in
            (day, upcoming.filter { calendar.isDate(max($0.start, date), inSameDayAs: day) })
        }
    }

    /// The entry under way at a moment, or the next one to come.
    ///
    /// - Parameter date: The moment to judge at.
    /// - Returns: The entry, or `nil` when nothing is left.
    func current(at date: Date) -> Entry? {
        entries.first { $0.isOn(at: date) }
            ?? entries.filter { $0.start > date }.min { $0.start < $1.start }
    }

    /// The moments after a date at which what ``current(at:)`` returns, or
    /// whether it is under way, changes.
    ///
    /// A complication's timeline is a list of these: the face redraws itself
    /// at each one with nothing running on the Watch.
    ///
    /// - Parameter date: The moment to look forward from.
    /// - Returns: Every start and end after it, in order, without repeats.
    func changes(after date: Date) -> [Date] {
        Set(entries.flatMap { [$0.start, $0.end] }.filter { $0 > date }).sorted()
    }

    /// The same snapshot without the moment it was built, for telling whether
    /// anything a wrist would see has changed.
    var content: WatchSnapshot {
        var copy = self
        copy.sentAt = .distantPast
        return copy
    }
}

extension WatchSnapshot.Entry {
    /// The address a complication or a Smart Stack card opens the Watch app
    /// at, to show this entry.
    var url: URL { URL(string: "poliverse-watch://entry/\(id)")! }

    /// The entry an address from ``url`` names.
    ///
    /// - Parameter url: An address the Watch app was opened with.
    /// - Returns: The entry's identity, or `nil` for any other address.
    static func id(from url: URL) -> Int? {
        guard url.scheme == "poliverse-watch", url.host() == "entry" else { return nil }
        return Int(url.lastPathComponent)
    }
}
