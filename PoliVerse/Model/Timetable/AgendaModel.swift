import Foundation
import Observation
import OSLog

/// Lectures, exams and deadlines from the Politecnico's agenda, merged with the
/// student's personal timetable.
///
/// ## What is held
///
/// The timetable is held **per week**: ``AgendaWeeks`` keyed by the Monday a week
/// starts on, and the deadlines, ``AgendaDeadlines``, a year ahead of the first week
/// asked for. ``officialEvents`` is the two merged, one entry per id. ``events`` is
/// that merged with the ``personalTimetable``'s lessons through ``TimetableMerge``,
/// and is what the screens read; ``events(on:)`` answers from an index built with it.
///
/// ## Loading
///
/// ``load(around:force:)`` asks for the weeks from a week behind a date to a month
/// ahead, and ``ensureLoaded(covering:)`` asks for the weeks around a date whose own
/// week is not held. Paging adds weeks rather than moving a window, so today's week
/// stays whatever the calendar is showing. The fetching, the joining of a week asked
/// for twice and how long a week stays fresh belong to a ``Loader``; two loads for
/// different weeks run together rather than one waiting for the other.
///
/// A week or the deadlines failing keeps what was held for them: an empty calendar is
/// indistinguishable from a free week. Sample lectures are never substituted for a
/// failure, since a room that does not exist would send someone to it.
///
/// ## Threads
///
/// The merge with the personal timetable and both indexes are built by
/// ``Compute/run(_:)`` off the main actor, and assigned here only when they changed.
@Observable
final class AgendaModel {
    /// Everything on the agenda for the weeks held, official and personal, in time
    /// order.
    private(set) var events: [AgendaEvent] = []
    /// ``events`` grouped by Rome day and sorted, rebuilt with them.
    ///
    /// Not observed: views read a day through ``events(on:)``, which hands them that
    /// day's ``Slice``. See `docs/metrickit-performance.md` §3.2 and §5.5.
    @ObservationIgnored private var eventsByDay: [Date: [AgendaEvent]] = [:]
    /// ``events`` grouped by lowercased title, each group in time order.
    ///
    /// Courses find their lessons by name, since the agenda carries no teaching code.
    /// Not observed, like ``eventsByDay``.
    @ObservationIgnored private var eventsByTitle: [String: [AgendaEvent]] = [:]

    /// One day's or one course's entries, observed on their own.
    ///
    /// Observation tracks whole properties. With the indexes observed, replacing
    /// ``events`` — which paging the calendar does week after week — invalidated
    /// every view that read any day or any course: Oggi under the calendar, the Corsi
    /// cards in their tab, the shell's accessory. A view now depends on the one slice
    /// it read, and a slice is reassigned only when its entries change.
    @Observable
    final class Slice {
        /// The entries, in time order.
        fileprivate(set) var events: [AgendaEvent] = []
    }
    /// The slice of every day asked for so far, by start of day.
    @ObservationIgnored private var daySlices: [Date: Slice] = [:]
    /// The slice of every course asked for so far, by lowercased name.
    @ObservationIgnored private var courseSlices: [String: Slice] = [:]
    /// The exams and deadlines, which Oggi's "In arrivo" lists; `nil` until asked for.
    @ObservationIgnored private var milestoneSlice: Slice?

    /// What the Politecnico's agenda sent, without personal lessons.
    ///
    /// ``TimetableHandover`` compares against this rather than ``events``, or personal
    /// lessons would confirm themselves.
    private(set) var officialEvents: [AgendaEvent] = []
    /// The student's personal timetable, whose lessons join ``events`` until the official
    /// agenda carries them. Setting it rebuilds ``events`` and rewrites the widgets' copy.
    var personalTimetable: PersonalTimetable? {
        didSet {
            guard personalTimetable != oldValue else { return }
            Task(name: "agenda rebuild") {
                await rebuild()
                saveForWidgets()
            }
        }
    }
    /// `true` while a load is in flight.
    private(set) var isLoading = false
    /// The last load's error, or `nil` when it succeeded. A failed deadlines fetch does
    /// not set it.
    private(set) var errorMessage: String?
    /// From the start of the first week held to the end of the last. `nil` before the
    /// first week arrives.
    private(set) var loadedRange: ClosedRange<Date>?
    /// Seconds since the week being looked at was fetched, or `nil` if never.
    private(set) var age: TimeInterval?

    /// The weeks held, by the Monday they start on, each in time order.
    @ObservationIgnored private var weeks: [Date: [AgendaEvent]] = [:]
    /// The deadlines held.
    @ObservationIgnored private var deadlines: [AgendaEvent] = []
    /// Whose agenda ``weeks`` and ``deadlines`` are, as ``Env/source``. A change
    /// discards them: they describe someone else, or sample data.
    @ObservationIgnored private var heldSource: String?
    /// The accounts whose offline copy has been restored this launch.
    @ObservationIgnored private var restored: Set<String> = []
    /// Loads in flight, which ``isLoading`` reports.
    @ObservationIgnored private var loadsInFlight = 0
    /// Bumped by each rebuild, so an older one finishing late does not overwrite a newer.
    @ObservationIgnored private var generation = 0

    /// Whose agenda to load, and the transport.
    private let account: any Account
    /// The weeks' fetches: joined, kept fresh, batched.
    /// Whether optional work should wait; see ``DevicePressure``.
    private let pressure: @Sendable () -> Bool
    private let weekLoader: Loader<AgendaWeeks>
    /// The deadlines' fetches.
    private let deadlineLoader: Loader<AgendaDeadlines>
    /// Where the widgets' copy lives.
    private let offline: OfflineStore
    /// Diagnostic log for this type, under the `agenda` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "agenda")

    /// The name of the widgets' copy of the merged agenda.
    nonisolated static let widgetCopyName = "agenda"

    /// Creates the model. Nothing is loaded or restored here.
    ///
    /// - Parameters:
    ///   - account: Whose agenda to load.
    ///   - offline: Where the widgets' copy lives.
    init(account: any Account, offline: OfflineStore = .shared,
         pressure: @escaping @Sendable () -> Bool = { DevicePressure.isHigh }) {
        self.account = account
        self.offline = offline
        self.pressure = pressure
        weekLoader = Loader(AgendaWeeks(), offline: offline)
        deadlineLoader = Loader(AgendaDeadlines(), offline: offline)
    }

    // MARK: - Loading

    /// Loads the weeks from a week behind a date to a month ahead, and the deadlines a
    /// year ahead of them.
    ///
    /// Weeks held and fresh are not asked for again; a week already being fetched is
    /// joined, not fetched twice. The lectures and the deadlines are fetched
    /// concurrently, and a deadline that also appears in the events feed is kept once.
    ///
    /// - Parameters:
    ///   - date: The date the student is looking at.
    ///   - force: Fetches even the weeks held fresh; set by pull-to-refresh.
    func load(around date: Date = .now, force: Bool = false) async {
        let env = Env(account)
        adopt(env)
        await restoreCache(env)

        guard env.isSample || env.matricola != nil else {
            errorMessage = AuthError.notAuthenticated.localizedDescription
            return
        }

        let wanted = AgendaWeeks.weeks(around: date)
        let deadlineKey = wanted.first ?? AgendaWeeks.week(of: date)
        // The weeks and deadlines as they were fetched: within their lifetime they
        // are served as they are, and nothing below asks the network.
        if await restoreFetched(wanted, deadlineKey: deadlineKey, env: env) { await rebuild() }
        var due = false
        for week in wanted where await weekLoader.isDue(week, env: env, force: force) { due = true; break }
        let deadlinesDue = await deadlineLoader.isDue(deadlineKey, env: env, force: force)
        guard due || deadlinesDue else { return }

        loadsInFlight += 1
        isLoading = true
        errorMessage = nil
        defer {
            loadsInFlight -= 1
            if loadsInFlight == 0 { isLoading = false }
        }

        async let lectures = fetchWeeks(wanted, env: env, force: force)
        async let fetchedDeadlines = fetchDeadlines(deadlineKey, env: env, force: force)
        let (weekResult, deadlineResult) = await (lectures, fetchedDeadlines)

        // The student may have signed out or switched to sample data meanwhile.
        guard heldSource == env.source else { return }

        switch weekResult {
        case .success(let snapshots):
            for (week, snapshot) in snapshots { weeks[week] = snapshot.value }
            if let current = snapshots[AgendaWeeks.week(of: date)] ?? snapshots.values.first {
                age = env.isSample ? nil : max(0, Date.now.timeIntervalSince(current.fetchedAt))
            }
        case .failure(let error):
            // Kept, not cleared: what is held was really this student's
            // timetable, and an empty calendar is indistinguishable from a
            // free week. Its age is shown instead.
            errorMessage = userFacingMessage(error)
        }
        if let fresh = deadlineResult { deadlines = fresh }

        await rebuild()
        if case .success = weekResult { saveForWidgets() }
    }

    /// Loads the weeks around a date when its own week, the one before or the two
    /// after are not held.
    ///
    /// Looking ahead is what keeps paging from waiting: the weeks next to the one on
    /// screen arrive while the student is still reading it, rather than after they
    /// have paged to an empty week. Only the week itself while the phone is hot or
    /// saving power (``DevicePressure``).
    ///
    /// - Parameter date: The date the student navigated to.
    func ensureLoaded(covering date: Date) async {
        let calendar = PoliMiDate.romeCalendar
        let neighbours = (pressure() ? [0] : [-7, 0, 7, 14]).map {
            AgendaWeeks.week(of: calendar.date(byAdding: .day, value: $0, to: date) ?? date)
        }
        guard heldSource != Env(account).source || neighbours.contains(where: { weeks[$0] == nil })
        else { return }
        log.debug("Navigated near a week not held; fetching around it")
        await load(around: date)
    }

    /// Fetches weeks through the loader.
    private func fetchWeeks(_ wanted: [Date], env: Env, force: Bool) async -> Result<[Date: Loader<AgendaWeeks>.Snapshot], any Error> {
        do {
            return .success(try await weekLoader.values(wanted, env: env, force: force))
        } catch {
            log.error("Agenda load failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Fetches the deadlines through their loader.
    ///
    /// A failure is logged and does not set ``errorMessage``: the timetable is the point
    /// and deadlines are additional.
    private func fetchDeadlines(_ key: Date, env: Env, force: Bool) async -> [AgendaEvent]? {
        do {
            return try await deadlineLoader.value(key, env: env, force: force).value
        } catch {
            log.error("Deadlines failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Discards what is held when it belongs to another account or to sample data.
    private func adopt(_ env: Env) {
        guard heldSource != env.source else { return }
        heldSource = env.source
        weeks = [:]
        deadlines = []
        age = nil
    }

    /// Puts the last known timetable on screen before any request answers, once per
    /// account, from the copy written for the widgets.
    ///
    /// Read and decoded off the main actor. Weeks a fetch filled while the file was
    /// being read keep the fetched entries.
    private func restoreCache(_ env: Env) async {
        // Sample data never reads the student's copy: it would flash their real
        // timetable before the samples replaced it.
        guard !env.isSample, let matricola = env.matricola, restored.insert(matricola).inserted,
              let entry = await offline.loaded([AgendaEvent].self, as: Self.widgetCopyName, account: matricola),
              heldSource == env.source
        else { return }
        let official = TimetableMerge.officialOnly(entry.value)
        let byWeek = Dictionary(grouping: official) { AgendaWeeks.week(of: $0.start) }
        for (week, events) in byWeek where weeks[week] == nil {
            weeks[week] = events.sorted { $0.start < $1.start }
        }
        if age == nil { age = entry.age }
        await rebuild()
    }

    /// Puts the kept copies of the weeks and deadlines a load wants in place, once per
    /// account and key, ahead of the widgets' merged copy.
    ///
    /// - Returns: Whether anything held changed.
    private func restoreFetched(_ wanted: [Date], deadlineKey: Date, env: Env) async -> Bool {
        guard !env.isSample, env.matricola != nil else { return false }
        var changed = false
        for week in wanted {
            guard let kept = await weekLoader.restore(week, env: env), heldSource == env.source,
                  weeks[week] != kept.value else { continue }
            weeks[week] = kept.value
            changed = true
        }
        if let kept = await deadlineLoader.restore(deadlineKey, env: env), heldSource == env.source,
           deadlines != kept.value {
            deadlines = kept.value
            changed = true
        }
        return changed
    }

    // MARK: - Building

    /// What a rebuild produces, off the main actor.
    private struct Built: Sendable {
        let official: [AgendaEvent]
        let events: [AgendaEvent]
        let byDay: [Date: [AgendaEvent]]
        let byTitle: [String: [AgendaEvent]]
        let range: ClosedRange<Date>?
    }

    /// Recomputes ``officialEvents``, ``events`` and the indexes from the weeks and
    /// deadlines held, off the main actor, and assigns what changed.
    private func rebuild() async {
        generation += 1
        let mine = generation
        let weeks = weeks
        let deadlines = deadlines
        let timetable = personalTimetable
        let built = await Compute.run { Self.build(weeks: weeks, deadlines: deadlines, timetable: timetable) }
        guard mine == generation else { return }
        if officialEvents != built.official { officialEvents = built.official }
        if loadedRange != built.range { loadedRange = built.range }
        guard events != built.events else { return }
        eventsByDay = built.byDay
        eventsByTitle = built.byTitle
        events = built.events
        refreshSlices()
    }

    /// The merge and the indexes, as a pure function.
    ///
    /// The events feed can carry a deadline too; one of each is kept, the feed's first.
    /// Personal lessons fill the span from the first week held to the end of the last,
    /// or the weeks around today before anything is held.
    private nonisolated static func build(weeks: [Date: [AgendaEvent]], deadlines: [AgendaEvent],
                                          timetable: PersonalTimetable?) -> Built {
        var known = Set<Int>()
        let official = (weeks.keys.sorted().flatMap { weeks[$0] ?? [] } + deadlines)
            .filter { known.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
        let calendar = PoliMiDate.romeCalendar
        let range: ClosedRange<Date>? = {
            guard let first = weeks.keys.min(), let last = weeks.keys.max(),
                  let end = calendar.date(byAdding: .day, value: 7, to: last) else { return nil }
            return first...end
        }()
        let interval = range.map { DateInterval(start: $0.lowerBound, end: $0.upperBound) }
            ?? DateInterval(start: calendar.date(byAdding: .day, value: -7, to: .now) ?? .now,
                            end: calendar.date(byAdding: .month, value: 1, to: .now) ?? .now)
        let events = TimetableMerge.merge(official: official, timetable: timetable, in: interval)
        return Built(official: official, events: events, byDay: index(events),
                     byTitle: titleIndex(events), range: range)
    }

    /// Brings every slice handed out so far in step with the indexes, touching only
    /// those whose entries changed.
    private func refreshSlices() {
        for (day, slice) in daySlices {
            let fresh = eventsByDay[day] ?? []
            if slice.events != fresh { slice.events = fresh }
        }
        for (target, slice) in courseSlices {
            let fresh = matching(target)
            if slice.events != fresh { slice.events = fresh }
        }
        if let milestoneSlice {
            let fresh = Self.milestones(in: events)
            if milestoneSlice.events != fresh { milestoneSlice.events = fresh }
        }
    }

    /// Writes the merged events to the app group and asks the agenda widgets to reload.
    ///
    /// Nothing else tells them the file changed, so without the reload the Lock Screen
    /// keeps the previous lecture until the system happens to grant one.
    ///
    /// Does nothing for a sample account or before the first week arrives.
    private func saveForWidgets() {
        guard !account.isSample, let matricola = account.matricola, loadedRange != nil else { return }
        offline.save(events, as: Self.widgetCopyName, account: matricola)
        WidgetReloader.request(WidgetKind.agenda)
    }

    // MARK: - Reading

    /// Everything on the agenda for one Rome day, in time order.
    ///
    /// - Parameter day: Any moment in the day.
    /// - Returns: The entries, from the index. Empty for a day in no week held.
    func events(on day: Date) -> [AgendaEvent] {
        let key = PoliMiDate.romeCalendar.startOfDay(for: day)
        if let slice = daySlices[key] { return slice.events }
        let slice = Slice()
        slice.events = eventsByDay[key] ?? []
        daySlices[key] = slice
        return slice.events
    }

    /// Groups events by Rome day and sorts each day in time order.
    ///
    /// - Parameter events: The entries to index.
    /// - Returns: The entries by start of day.
    nonisolated static func index(_ events: [AgendaEvent]) -> [Date: [AgendaEvent]] {
        let calendar = PoliMiDate.romeCalendar
        return Dictionary(grouping: events) { calendar.startOfDay(for: $0.start) }
            .mapValues { $0.sorted { $0.start < $1.start } }
    }

    /// The exams and deadlines on the agenda, in time order.
    ///
    /// Observed on their own, like a day: Oggi's "In arrivo" lists only these, and
    /// read the whole agenda before, so every week paged in the calendar redrew it.
    ///
    /// - Returns: The exams and deadlines held.
    func milestones() -> [AgendaEvent] {
        let slice = milestoneSlice ?? {
            let slice = Slice()
            slice.events = Self.milestones(in: events)
            milestoneSlice = slice
            return slice
        }()
        return slice.events
    }

    /// The exams and deadlines among some events, in their order.
    ///
    /// - Parameter events: The events, in time order.
    /// - Returns: Those that are exams or deadlines.
    private nonisolated static func milestones(in events: [AgendaEvent]) -> [AgendaEvent] {
        events.filter { $0.kind == .exam || $0.kind == .deadline }
    }

    /// Everything on the agenda that belongs to a course, matched by name, in time
    /// order.
    ///
    /// A title matches when it contains the course's name or is contained in it — the
    /// same normalised match the course cards and the course page have always used.
    ///
    /// - Parameter name: The course's name.
    /// - Returns: The matching entries, earliest first.
    func events(matchingCourse name: String) -> [AgendaEvent] {
        let target = name.lowercased()
        if let slice = courseSlices[target] { return slice.events }
        let slice = Slice()
        slice.events = matching(target)
        courseSlices[target] = slice
        return slice.events
    }

    /// The entries whose lowercased title contains a lowercased course name, or is
    /// contained in it.
    ///
    /// - Parameter target: The lowercased course name.
    /// - Returns: The matching entries, earliest first.
    private func matching(_ target: String) -> [AgendaEvent] {
        let groups = eventsByTitle.filter { title, _ in title.contains(target) || target.contains(title) }
        if groups.count == 1, let only = groups.first { return only.value }
        return groups.values.flatMap { $0 }.sorted { $0.start < $1.start }
    }

    /// Groups events by lowercased title and sorts each group in time order.
    ///
    /// - Parameter events: The entries to index.
    /// - Returns: The entries by title.
    nonisolated static func titleIndex(_ events: [AgendaEvent]) -> [String: [AgendaEvent]] {
        Dictionary(grouping: events) { $0.title.lowercased() }
            .mapValues { $0.sorted { $0.start < $1.start } }
    }

    /// The days in the weeks held that have something on them, which dots the week
    /// strip.
    ///
    /// - Returns: The starts of those days, in Rome.
    func daysWithEvents() -> Set<Date> {
        // Read through ``events`` so a view asking stays observing: the index is not.
        _ = events
        return Set(eventsByDay.keys)
    }

    /// The lectures on one day, which is what a timetable shows.
    ///
    /// - Parameter day: Any moment in the day.
    /// - Returns: The lectures, in time order.
    func lectures(on day: Date) -> [AgendaEvent] {
        events(on: day).filter { $0.kind == .lecture }
    }

    /// The first entry that has not yet ended, for the Oggi summary.
    ///
    /// - Parameter moment: The moment to measure from.
    /// - Returns: The entry, or `nil` when nothing in the weeks held is still ahead.
    func nextEvent(after moment: Date = .now) -> AgendaEvent? {
        events.first { $0.end > moment }
    }
}

/// ``AgendaModel`` satisfies ``TimetablePublishing`` as it stands.
///
/// Declared here rather than beside the protocol: ``TimetablePublishing``
/// refines `Sendable`, and a `Sendable` conformance stated in another file is
/// retroactive.
extension AgendaModel: TimetablePublishing {}
