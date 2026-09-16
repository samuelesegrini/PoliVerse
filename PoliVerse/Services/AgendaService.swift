import Foundation
import Observation
import OSLog

/// Lectures, exams and deadlines from the agenda endpoint.
///
/// `GET {agenda}/v1/matricola/{matricola}/events?start_date=yyyy-MM-dd&n_events=N`
///
/// The host and path moved — PoliFemo's
/// `polimiapp.polimi.it/polimi_app/agenda/api/me/{matricola}/events` now 404s —
/// but the query contract did not. The endpoint still names `start_date` and
/// `n_events` in its own 400 response, so the parameters, and very likely the
/// response shape, are unchanged.
///
/// The endpoint filters server-side: alongside `start_date` and `n_events` it
/// accepts `end_date`, which PoliFemo's version did not use. The official app
/// asks for `start_date = today, end_date = today + 1 month`, so that is what
/// this does — no more fetching 200 events and discarding most of them.
@Observable
final class AgendaService {
    private(set) var events: [AgendaEvent] = [] {
        didSet { eventsByDay = Self.index(events) }
    }
    /// `events`, grouped by Rome day and sorted, rebuilt whenever they change.
    ///
    /// The week strip asked for each of its seven days on every body pass, and
    /// each ask filtered and sorted the whole window on the main thread. One
    /// pass on write is cheaper than seven on read, every frame something
    /// changes (`docs/metrickit-performance.md` §3.2).
    private var eventsByDay: [Date: [AgendaEvent]] = [:]
    /// What the Politecnico's agenda said, without personal lessons: the
    /// hand-over compares against this, or personal lessons would confirm
    /// themselves.
    private(set) var officialEvents: [AgendaEvent] = []
    /// The personal timetable, whose lessons join ``events`` until the
    /// official agenda has them.
    var personalTimetable: PersonalTimetable? {
        didSet {
            guard personalTimetable != oldValue else { return }
            rebuild()
            saveForWidgets()
        }
    }
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The span currently held, so navigating past its edge can fetch more.
    private(set) var loadedRange: ClosedRange<Date>?

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "agenda")
    private var window = LoadWindow()
    private var slot = CachedSlot<[AgendaEvent]>(name: "agenda")
    /// How old the events on screen are.
    private(set) var age: TimeInterval?

    /// Identifies the data currently held, so a change of account — or of the
    /// sample-data toggle — always reloads instead of waiting out the window.
    private var source: String {
        session.useMockData ? "mock" : (session.student?.matricola ?? "anonymous")
    }


    /// A cap rather than a target, now that the range is filtered server-side.
    /// A full timetable month is well under this.
    private let pageSize = 200

    /// How far either side of the requested date to fetch. The official app
    /// asks for a month ahead; a week behind costs nothing and means stepping
    /// back a week does not trigger a round trip.
    private let lookBehind = DateComponents(day: -7)
    private let lookAhead = DateComponents(month: 1)

    init(session: Session) {
        self.session = session
    }

    /// Last known timetable, shown before any request. Restored here rather
    /// than in `init()`, where the matricola is not known yet.
    private func restoreCache() {
        guard let cached = slot.restore(for: session.student?.matricola) else { return }
        officialEvents = TimetableMerge.officialOnly(cached)
        rebuild()
        age = slot.age
    }

    /// Fetches a window around `date`, replacing whatever was held.
    /// - Parameter force: set by pull-to-refresh; see ``LoadWindow``.
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

        if session.useMockData {
            loadedRange = from...to
            officialEvents = MockData.agendaEvents(around: date)
            rebuild()
            window.markLoaded(source: source)
            return
        }

        guard let matricola = session.student?.matricola else {
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

    private func rebuild() {
        let calendar = PoliMiDate.romeCalendar
        let interval = loadedRange.map { DateInterval(start: $0.lowerBound, end: $0.upperBound) }
            ?? DateInterval(start: calendar.date(byAdding: lookBehind, to: .now) ?? .now,
                            end: calendar.date(byAdding: lookAhead, to: .now) ?? .now)
        events = TimetableMerge.merge(official: officialEvents, timetable: personalTimetable, in: interval)
    }

    /// Saved merged: the widgets show personal lessons too.
    private func saveForWidgets() {
        guard !session.useMockData, let matricola = session.student?.matricola, loadedRange != nil else { return }
        slot.save(events, for: matricola)
        // The widgets read this file; nothing else tells them it changed.
        // Without this the Lock Screen keeps last night's lecture until the
        // system happens to grant a reload, which can be hours.
        WidgetReloader.request(WidgetKind.agenda)
    }

    /// Whether the held window already spans `date`.
    private func covers(_ date: Date) -> Bool {
        loadedRange?.contains(date) ?? false
    }

    /// Fetches only if `date` falls outside what is already held.
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

    private func fetchEvents(matricola: String, from: Date, to: Date) async -> [AgendaEvent]? {
        do {
            let dtos = try await session.api.send(
                APIRequest(
                    host: .agenda,
                    path: "/v1/matricola/\(matricola)/events",
                    query: [
                        .init(name: "start_date", value: PoliMiDate.queryString(from)),
                        .init(name: "end_date", value: PoliMiDate.queryString(to)),
                        .init(name: "n_events", value: String(pageSize)),
                    ]
                ),
                as: [AgendaEventDTO].self
            )
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

    /// Deadlines are their own endpoint and worth a longer horizon.
    private func fetchDeadlines(matricola: String, from: Date) async -> [AgendaEvent]? {
        let to = PoliMiDate.romeCalendar.date(byAdding: .year, value: 1, to: from) ?? from
        do {
            let dtos = try await session.api.send(
                APIRequest(
                    host: .agenda,
                    path: "/v1/matricola/\(matricola)/events/deadlines",
                    query: [
                        .init(name: "start_date", value: PoliMiDate.queryString(from)),
                        .init(name: "end_date", value: PoliMiDate.queryString(to)),
                    ]
                ),
                as: [AgendaEventDTO].self
            )
            let parsed = dtos.compactMap { $0.toEvent() }
            log.notice("agenda \(PoliMiDate.queryString(from), privacy: .public)…\(PoliMiDate.queryString(to), privacy: .public): \(dtos.count, privacy: .public) deadlines, \(parsed.count, privacy: .public) usable")
            return parsed
        } catch {
            // Not fatal: the timetable is the point, deadlines are a bonus.
            log.error("Deadlines failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Events on a given day, in Rome time.
    func events(on day: Date) -> [AgendaEvent] {
        eventsByDay[PoliMiDate.romeCalendar.startOfDay(for: day)] ?? []
    }

    nonisolated static func index(_ events: [AgendaEvent]) -> [Date: [AgendaEvent]] {
        let calendar = PoliMiDate.romeCalendar
        return Dictionary(grouping: events) { calendar.startOfDay(for: $0.start) }
            .mapValues { $0.sorted { $0.start < $1.start } }
    }

    /// Days in the loaded window that actually have something on them, used to
    /// dot the week strip.
    func daysWithEvents() -> Set<Date> {
        Set(eventsByDay.keys)
    }

    /// Lectures on a given day, which is what a timetable shows.
    func lectures(on day: Date) -> [AgendaEvent] {
        events(on: day).filter { $0.kind == .lecture }
    }

    /// The next event from now, for the Home screen summary.
    func nextEvent(after moment: Date = .now) -> AgendaEvent? {
        events.first { $0.end > moment }
    }
}
