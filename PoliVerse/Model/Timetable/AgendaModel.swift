import Foundation
import Observation
import OSLog

/// Lectures, exams and deadlines from the Politecnico's agenda, merged with the
/// student's personal timetable.
///
/// Two endpoints on the agenda host:
/// `GET {agenda}/v1/matricola/{matricola}/events` for the timetable window, and
/// `…/events/deadlines` for deadlines, which are sparse and worth a year's horizon of
/// their own. Both filter server-side on `start_date` and `end_date`.
///
/// ## What is held
///
/// ``officialEvents`` is what the server sent. ``events`` is that merged with the
/// ``personalTimetable``'s lessons through ``TimetableMerge``, and is what the screens
/// read. ``events(on:)`` answers from an index rebuilt on write rather than filtering
/// the window on every read.
///
/// ## Loading
///
/// ``load(around:force:)`` fetches a window from a week behind the date to a month
/// ahead, and ``ensureLoaded(covering:)`` extends it when the student navigates past
/// its edge. A load that gets nothing keeps what is held and reports its age: an empty
/// calendar is indistinguishable from a free week. Sample lectures are never
/// substituted for a failure, since a room that does not exist would send someone to
/// it.
///
/// This model fetches by hand rather than through ``Store``, because its window is a
/// parameter of the request.
@Observable
final class AgendaModel {
    /// Everything on the agenda for the loaded window, official and personal, in time
    /// order. Setting it rebuilds the per-day index.
    private(set) var events: [AgendaEvent] = [] {
        didSet { eventsByDay = Self.index(events) }
    }
    /// ``events`` grouped by Rome day and sorted, rebuilt whenever they change.
    ///
    /// The week strip asks for each of its seven days on every body pass, so one pass on
    /// write is cheaper than seven filters and sorts on read.
    ///
    /// See `docs/metrickit-performance.md` §3.2.
    private var eventsByDay: [Date: [AgendaEvent]] = [:]
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
            rebuild()
            saveForWidgets()
        }
    }
    /// `true` while a load is in flight.
    private(set) var isLoading = false
    /// The last load's error, or `nil` when it succeeded. A failed deadlines fetch does
    /// not set it.
    private(set) var errorMessage: String?
    /// The span currently held, so navigating past its edge can fetch more. `nil` before
    /// the first successful load.
    private(set) var loadedRange: ClosedRange<Date>?

    /// Whose agenda to load, and the transport.
    private let account: any Account
    /// Diagnostic log for this type, under the `agenda` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "agenda")
    /// Suppresses redundant refreshes of the held window.
    private var window = LoadWindow()
    /// The offline copy, holding the merged events so the widgets see personal lessons
    /// too.
    private var slot = CachedSlot<[AgendaEvent]>(name: "agenda")
    /// Seconds since the events on screen were fetched, or `nil` if never.
    private(set) var age: TimeInterval?

    /// Identifies the data currently held, so a change of account — or of the sample-data
    /// toggle — reloads rather than waiting out the load window.
    private var source: String {
        account.isSample ? "mock" : (account.matricola ?? "anonymous")
    }


    /// The `n_events` cap. A cap rather than a target, now that the span is filtered
    /// server-side; a full timetable month is well under it.
    private let pageSize = 200

    /// How far behind the requested date to fetch. A week costs nothing and means stepping
    /// back does not trigger a round trip.
    private let lookBehind = DateComponents(day: -7)
    /// How far ahead of the requested date to fetch, matching the official client.
    private let lookAhead = DateComponents(month: 1)

    /// Creates the model. Nothing is loaded or restored here.
    ///
    /// - Parameter account: Whose agenda to load.
    init(account: any Account) {
        self.account = account
    }

    /// Puts the last known timetable on screen before any request answers.
    ///
    /// Called from ``load(around:force:)`` rather than from `init()`, where the matricola
    /// is not known yet. Does nothing after the first restore for an account.
    private func restoreCache() {
        guard let cached = slot.restore(for: account.matricola) else { return }
        officialEvents = TimetableMerge.officialOnly(cached)
        rebuild()
        age = slot.age
    }

    /// Fetches a window around a date, replacing whatever was held.
    ///
    /// Returns immediately when a load is in flight, or when the load window has not
    /// expired and the held span already covers the date. The lectures and the deadlines
    /// are fetched concurrently, and a deadline that also appears in the events feed is
    /// kept once.
    ///
    /// - Parameters:
    ///   - date: The date to centre the window on.
    ///   - force: Bypasses the load window; set by pull-to-refresh.
    func load(around date: Date = .now, force: Bool = false) async {
        guard !isLoading,
              window.shouldLoad(force: force, source: source) || !covers(date)
        else { return }
        isLoading = true
        errorMessage = nil
        // After the guard, so a skipped call is not timed as a fast one.
        let interval = PerfSignpost.begin(.agendaLoad)
        defer {
            isLoading = false
            PerfSignpost.end(interval)
        }

        let calendar = PoliMiDate.romeCalendar
        let from = calendar.date(byAdding: lookBehind, to: date) ?? date
        let to = calendar.date(byAdding: lookAhead, to: date) ?? date

        restoreCache()

        if account.isSample {
            loadedRange = from...to
            officialEvents = AgendaEvent.samples(around: date)
            rebuild()
            window.markLoaded(source: source)
            return
        }

        guard let matricola = account.matricola else {
            errorMessage = AuthError.notAuthenticated.localizedDescription
            return
        }

        // Lectures and deadlines are separate endpoints. Deadlines look a year
        // ahead upstream because they are sparse and worth seeing early, so
        // they are fetched over their own span rather than this window.
        async let lectures = fetchEvents(matricola: matricola, from: from, to: to)
        async let deadlines = fetchDeadlines(matricola: matricola, from: from)

        let (fetched, fetchedDeadlines) = await (lectures, deadlines)

        guard fetched != nil || fetchedDeadlines != nil else {
            // Kept, not cleared: what is held was really this student's
            // timetable, and an empty calendar is indistinguishable from a
            // free week. Its age is shown instead.
            //
            // Still no mock fallback: sample lectures shown as real would
            // send someone to a room that does not exist.
            return
        }

        // A deadline can also appear in the events feed; keep one of each.
        var merged = fetched ?? []
        let known = Set(merged.map(\.id))
        merged += (fetchedDeadlines ?? []).filter { !known.contains($0.id) }

        loadedRange = from...to
        officialEvents = merged.sorted { $0.start < $1.start }
        rebuild()
        window.markLoaded(source: source)
        saveForWidgets()
        age = slot.age
    }

    /// Recomputes ``events`` by merging the personal timetable into ``officialEvents``
    /// over the held span, or over a default span when nothing is loaded yet.
    private func rebuild() {
        let calendar = PoliMiDate.romeCalendar
        let interval = loadedRange.map { DateInterval(start: $0.lowerBound, end: $0.upperBound) }
            ?? DateInterval(start: calendar.date(byAdding: lookBehind, to: .now) ?? .now,
                            end: calendar.date(byAdding: lookAhead, to: .now) ?? .now)
        events = TimetableMerge.merge(official: officialEvents, timetable: personalTimetable, in: interval)
    }

    /// Writes the merged events to the app group and asks the agenda widgets to reload.
    ///
    /// Nothing else tells them the file changed, so without the reload the Lock Screen
    /// keeps the previous lecture until the system happens to grant one.
    ///
    /// Does nothing for a sample account or before the first successful load.
    private func saveForWidgets() {
        guard !account.isSample, let matricola = account.matricola, loadedRange != nil else { return }
        slot.save(events, for: matricola)
        // The widgets read this file; nothing else tells them it changed.
        // Without this the Lock Screen keeps last night's lecture until the
        // system happens to grant a reload, which can be hours.
        WidgetReloader.request(WidgetKind.agenda)
    }

    /// Whether the held span includes a date.
    ///
    /// - Parameter date: The date to test.
    /// - Returns: `false` before the first successful load.
    private func covers(_ date: Date) -> Bool {
        loadedRange?.contains(date) ?? false
    }

    /// Fetches only if a date falls outside the span already held.
    ///
    /// The fetch is forced, since the span genuinely does not hold the date and freshness
    /// is beside the point.
    ///
    /// - Parameter date: The date the student navigated to.
    func ensureLoaded(covering date: Date) async {
        guard loadedRange != nil else {
            await load(around: date)
            return
        }
        guard !covers(date) else { return }
        log.debug("Navigated outside the loaded window; fetching around it")
        // Forced: the window genuinely does not hold this date, so freshness
        // is beside the point.
        await load(around: date, force: true)
    }

    /// Fetches the timetable events for a span.
    ///
    /// Entries with unparseable timestamps are dropped rather than placed on a guessed
    /// day. A failure sets ``errorMessage``.
    ///
    /// - Parameters:
    ///   - matricola: Whose agenda to fetch.
    ///   - from: Start of the span.
    ///   - to: End of the span.
    /// - Returns: The entries, or `nil` on failure.
    private func fetchEvents(matricola: String, from: Date, to: Date) async -> [AgendaEvent]? {
        do {
            let data = try await account.http.data(for: APIRequest(
                host: .agenda,
                path: "/v1/matricola/\(matricola)/events",
                query: [
                    .init(name: "start_date", value: PoliMiDate.queryString(from)),
                    .init(name: "end_date", value: PoliMiDate.queryString(to)),
                    .init(name: "n_events", value: String(pageSize)),
                ]
            ))
            let dtos = try await BackgroundJSON.decode([AgendaEventDTO].self, from: data,
                                                       iso8601Dates: true)
            // Drop entries with unparseable timestamps rather than guessing at
            // a date and showing a lecture on the wrong day.
            let parsed = dtos.compactMap { $0.toEvent() }
            // The range is logged with the count because the two are only
            // meaningful together: an empty agenda and a window that has
            // slipped past the events look identical without it.
            log.notice("agenda \(PoliMiDate.queryString(from), privacy: .public)…\(PoliMiDate.queryString(to), privacy: .public): \(dtos.count, privacy: .public) events, \(parsed.count, privacy: .public) usable")
            return parsed
        } catch {
            log.error("Agenda load failed: \(error.localizedDescription)")
            errorMessage = userFacingMessage(error)
            return nil
        }
    }

    /// Fetches deadlines for the year after a date.
    ///
    /// A failure is logged and does not set ``errorMessage``: the timetable is the point
    /// and deadlines are additional.
    ///
    /// - Parameters:
    ///   - matricola: Whose deadlines to fetch.
    ///   - from: Start of the span.
    /// - Returns: The deadlines, or `nil` on failure.
    private func fetchDeadlines(matricola: String, from: Date) async -> [AgendaEvent]? {
        let to = PoliMiDate.romeCalendar.date(byAdding: .year, value: 1, to: from) ?? from
        do {
            let data = try await account.http.data(for: APIRequest(
                host: .agenda,
                path: "/v1/matricola/\(matricola)/events/deadlines",
                query: [
                    .init(name: "start_date", value: PoliMiDate.queryString(from)),
                    .init(name: "end_date", value: PoliMiDate.queryString(to)),
                ]
            ))
            let dtos = try await BackgroundJSON.decode([AgendaEventDTO].self, from: data,
                                                       iso8601Dates: true)
            let parsed = dtos.compactMap { $0.toEvent() }
            log.notice("agenda \(PoliMiDate.queryString(from), privacy: .public)…\(PoliMiDate.queryString(to), privacy: .public): \(dtos.count, privacy: .public) deadlines, \(parsed.count, privacy: .public) usable")
            return parsed
        } catch {
            // Not fatal: the timetable is the point, deadlines are a bonus.
            log.error("Deadlines failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Everything on the agenda for one Rome day, in time order.
    ///
    /// - Parameter day: Any moment in the day.
    /// - Returns: The entries, from the index. Empty for a day outside the held span.
    func events(on day: Date) -> [AgendaEvent] {
        eventsByDay[PoliMiDate.romeCalendar.startOfDay(for: day)] ?? []
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

    /// The days in the held span that have something on them, which dots the week strip.
    ///
    /// - Returns: The starts of those days, in Rome.
    func daysWithEvents() -> Set<Date> {
        Set(eventsByDay.keys)
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
    /// - Returns: The entry, or `nil` when nothing in the held span is still ahead.
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
