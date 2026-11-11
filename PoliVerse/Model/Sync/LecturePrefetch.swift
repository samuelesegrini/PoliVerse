import Foundation
import OSLog

/// Prepares what the lectures of the next hour need, within the speculative budget.
///
/// Run after a foreground pass and in a background refresh: the two moments the
/// app is awake that it does not choose (R19). It asks ``TimetablePrefetch`` what
/// is wanted, the budget how much may go, and hands each item to whoever can
/// warm it. The requests themselves run in the speculative lane of
/// ``RequestGate``, which also counts them; when the student opens the room or
/// the course, the loaders find them fresh and send nothing (R20).
///
/// The warming is passed in rather than named, so the coordination is tested
/// without the services it drives.
@MainActor
final class LecturePrefetch {
    /// The timetable's entries.
    private let lectures: () -> [AgendaEvent]
    /// Warms a room's day, plan and equipment.
    private let room: ([String], Date) async -> Void
    /// Warms a course's page.
    private let course: (String) async -> Void
    /// How many of some wanted speculative requests may go out now.
    private let allowance: (Int) async -> Int
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "prefetch")

    /// Creates the runner.
    ///
    /// - Parameters:
    ///   - lectures: Reads the timetable's entries.
    ///   - room: Warms a room's day, plan and equipment from the names the
    ///     timetable gives it.
    ///   - course: Warms a course's page from a lecture's title.
    ///   - allowance: How many of some speculative requests may go out now.
    ///     The app's gate by default.
    init(lectures: @escaping () -> [AgendaEvent],
         room: @escaping ([String], Date) async -> Void,
         course: @escaping (String) async -> Void,
         allowance: ((Int) async -> Int)? = nil) {
        self.lectures = lectures
        self.room = room
        self.course = course
        self.allowance = allowance ?? { @Sendable count in await RequestGate.shared.allowance(for: count) }
    }

    /// Prepares what the next hour's lectures need.
    ///
    /// - Parameter now: The current moment.
    /// - Returns: The items handed over, for the log and the tests.
    @discardableResult
    func run(now: Date = .now) async -> [PrefetchItem] {
        let wanted = TimetablePrefetch.wanted(now: now, lectures: lectures())
        guard !wanted.isEmpty else { return [] }
        let granted = await allowance(wanted.reduce(0) { $0 + $1.cost })
        let items = TimetablePrefetch.fitting(wanted, allowance: granted)
        log.notice("prefetch: \(items.count, privacy: .public) of \(wanted.count, privacy: .public) items")
        for item in items {
            switch item {
            case .room(let names, let day): await room(names, day)
            case .course(let title): await course(title)
            }
        }
        return items
    }
}
