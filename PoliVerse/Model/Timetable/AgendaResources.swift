import Foundation
import OSLog

/// The agenda's timetable, one week at a time.
///
/// Keyed by the Monday a week starts on, in Rome. Paging the calendar asks for new
/// keys rather than moving a window, so the week with today in it is its own key and
/// can never be dropped by looking elsewhere.
///
/// `GET {agenda}/v1/matricola/{matricola}/events` filters server-side on
/// `start_date` and `end_date`, so contiguous weeks go out as one request: the weeks a
/// load wants cost one round trip, not one each. Each entry is filed under the week
/// it starts in, and a week asked for with nothing in it is held as empty.
nonisolated struct AgendaWeeks: Resource {
    typealias Key = Date
    typealias Value = [AgendaEvent]

    static let id = "agenda-week"
    /// Each week is kept on disk as fetched, so a launch within ``ttl`` of the last
    /// fetch shows it without asking. The merged agenda the widgets read is written
    /// separately by the model, and is what the first frame restores from.
    static let persistence = Persistence.offline
    /// Two years of weeks, far more than a session pages through.
    static let capacity = 104
    static let signpost: PerfSignpost.Name? = .agendaLoad

    /// The `n_events` cap for a request, never below the official client's 200: forty
    /// entries a week, which a full week of lectures, labs and tutorials stays under.
    /// A cap rather than a target, since the span is filtered server-side.
    static func pageSize(weeks: Int) -> Int { max(200, 40 * weeks) }

    /// One file per week, named by its Monday.
    func storageName(for key: Date) -> String { "\(Self.id)-\(PoliMiDate.queryString(key))" }
    /// The most weeks one request covers: the most a load around a date asks for, a
    /// week behind to a month ahead, so a load is always one request.
    static let weeksPerRequest = 7

    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "agenda")

    /// The Monday starting the Rome week that contains a date.
    ///
    /// - Parameter date: Any moment.
    /// - Returns: The week's start.
    static func week(of date: Date) -> Date {
        let calendar = PoliMiDate.romeCalendar
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The weeks a load around a date wants: from the week of seven days before it to
    /// the week of a month after, matching the official client's month ahead with a
    /// week behind that costs nothing and means stepping back does not ask again.
    ///
    /// - Parameter date: The date the student is looking at.
    /// - Returns: The weeks' starts, in order.
    static func weeks(around date: Date) -> [Date] {
        let calendar = PoliMiDate.romeCalendar
        let first = week(of: calendar.date(byAdding: .day, value: -7, to: date) ?? date)
        let last = week(of: calendar.date(byAdding: .month, value: 1, to: date) ?? date)
        var weeks: [Date] = []
        var current = first
        while current <= last {
            weeks.append(current)
            current = calendar.date(byAdding: .day, value: 7, to: current) ?? last.addingTimeInterval(1)
        }
        return weeks
    }

    @concurrent
    func fetch(_ key: Date, env: Env, previous: [AgendaEvent]?) async throws -> [AgendaEvent] {
        try await fetch([key], env: env, previous: [:])[key] ?? []
    }

    @concurrent
    func fetch(_ keys: [Date], env: Env, previous: [Date: [AgendaEvent]]) async throws -> [Date: [AgendaEvent]] {
        guard let matricola = env.matricola else { throw AuthError.notAuthenticated }
        let runs = Self.runs(keys.sorted())
        return try await withThrowingTaskGroup(of: [Date: [AgendaEvent]].self) { group in
            for run in runs {
                group.addTask(name: "agenda weeks") {
                    try await Self.fetch(run: run, matricola: matricola, http: env.http)
                }
            }
            var all: [Date: [AgendaEvent]] = [:]
            for try await part in group { all.merge(part) { first, _ in first } }
            return all
        }
    }

    func sample(_ key: Date) -> [AgendaEvent]? {
        let samples = AgendaEvent.samples(around: key)
        // The sample week numbers its entries from one; any week but the current
        // one is renumbered, or two sample weeks would collapse into one by id.
        guard key != Self.week(of: .now) else { return samples }
        let offset = 1_000 * (Int(key.timeIntervalSince1970 / (7 * 86_400)) % 1_000_000)
        return samples.map { $0.renumbered(offset + $0.id) }
    }

    /// Contiguous weeks, split so none is longer than ``weeksPerRequest``.
    ///
    /// - Parameter sorted: Week starts, in order.
    /// - Returns: The runs, each in order.
    static func runs(_ sorted: [Date]) -> [[Date]] {
        var runs: [[Date]] = []
        for week in sorted {
            // A week is seven days give or take the daylight-saving hour.
            if let last = runs.last?.last, runs[runs.count - 1].count < weeksPerRequest,
               abs(week.timeIntervalSince(last) - 7 * 86_400) < 3 * 3600 {
                runs[runs.count - 1].append(week)
            } else {
                runs.append([week])
            }
        }
        return runs
    }

    /// One request for a run of contiguous weeks, filed by week.
    private static func fetch(run: [Date], matricola: String, http: any HTTP) async throws -> [Date: [AgendaEvent]] {
        let calendar = PoliMiDate.romeCalendar
        guard let from = run.first, let lastWeek = run.last,
              let to = calendar.date(byAdding: .day, value: 7, to: lastWeek) else { return [:] }
        let data = try await http.data(for: APIRequest(
            host: .agenda,
            path: "/v1/matricola/\(matricola)/events",
            query: [
                .init(name: "start_date", value: PoliMiDate.queryString(from)),
                .init(name: "end_date", value: PoliMiDate.queryString(to)),
                .init(name: "n_events", value: String(pageSize(weeks: run.count))),
            ]
        ))
        let dtos = try JSONDecoder.iso8601.decode([AgendaEventDTO].self, from: data)
        // Dropped rather than placed on a guessed day: an entry that cannot be
        // placed in time would show a lecture on the wrong day.
        let parsed = dtos.compactMap { $0.toEvent() }
        // The range is logged with the count because the two are only meaningful
        // together: an empty agenda and a window that has slipped past the events
        // look identical without it.
        log.notice("agenda \(PoliMiDate.queryString(from), privacy: .public)…\(PoliMiDate.queryString(to), privacy: .public): \(dtos.count, privacy: .public) events, \(parsed.count, privacy: .public) usable")
        var byWeek = Dictionary(uniqueKeysWithValues: run.map { ($0, [AgendaEvent]()) })
        for event in parsed {
            let week = week(of: event.start)
            if byWeek[week] != nil { byWeek[week]?.append(event) }
        }
        return byWeek.mapValues { $0.sorted { $0.start < $1.start } }
    }
}

/// The agenda's deadlines, a year ahead of a week.
///
/// `…/events/deadlines`, over its own span: deadlines are sparse and worth seeing
/// early, so they look a year ahead where the timetable looks a month. Keyed by the
/// week the span starts on.
nonisolated struct AgendaDeadlines: Resource {
    typealias Key = Date
    typealias Value = [AgendaEvent]

    static let id = "agenda-deadlines"
    /// Kept on disk like the weeks, so a launch within ``ttl`` asks for neither.
    static let persistence = Persistence.offline
    static let capacity = 8

    /// One file per span, named by the week it starts on.
    func storageName(for key: Date) -> String { "\(Self.id)-\(PoliMiDate.queryString(key))" }

    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "agenda")

    @concurrent
    func fetch(_ key: Date, env: Env, previous: [AgendaEvent]?) async throws -> [AgendaEvent] {
        guard let matricola = env.matricola else { throw AuthError.notAuthenticated }
        let to = PoliMiDate.romeCalendar.date(byAdding: .year, value: 1, to: key) ?? key
        let data = try await env.http.data(for: APIRequest(
            host: .agenda,
            path: "/v1/matricola/\(matricola)/events/deadlines",
            query: [
                .init(name: "start_date", value: PoliMiDate.queryString(key)),
                .init(name: "end_date", value: PoliMiDate.queryString(to)),
            ]
        ))
        let dtos = try JSONDecoder.iso8601.decode([AgendaEventDTO].self, from: data)
        let parsed = dtos.compactMap { $0.toEvent() }
        Self.log.notice("agenda \(PoliMiDate.queryString(key), privacy: .public)…\(PoliMiDate.queryString(to), privacy: .public): \(dtos.count, privacy: .public) deadlines, \(parsed.count, privacy: .public) usable")
        return parsed
    }

    /// The sample weeks carry their own deadline.
    func sample(_ key: Date) -> [AgendaEvent]? { [] }
}

extension AgendaEvent {
    /// The same entry under another identifier.
    ///
    /// - Parameter id: The new identifier.
    /// - Returns: The copy.
    nonisolated func renumbered(_ id: Int) -> AgendaEvent {
        AgendaEvent(id: id, title: title, start: start, end: end, kind: kind, room: room,
                    roomAcronym: roomAcronym, calendarName: calendarName, details: details,
                    subtype: subtype, tags: tags)
    }
}

extension JSONDecoder {
    /// A decoder reading ISO 8601 dates, for a fetch already off the main actor.
    nonisolated static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
