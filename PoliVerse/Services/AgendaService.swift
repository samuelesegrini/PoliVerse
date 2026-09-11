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
    private(set) var events: [AgendaEvent] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Start of the window currently held, so we know when a scroll needs more.
    private(set) var loadedFrom: Date?

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "agenda")

    /// A cap rather than a target, now that the range is filtered server-side.
    /// A full timetable month is well under this.
    private let pageSize = 200

    /// How far ahead to ask for, matching the official app.
    private let window = DateComponents(month: 1)

    init(session: Session) {
        self.session = session
    }

    func load(from startDate: Date = .now) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if session.useMockData {
            events = MockData.agendaEvents(around: startDate)
            loadedFrom = startDate
            return
        }

        guard let matricola = session.student?.matricola else {
            errorMessage = AuthError.notAuthenticated.localizedDescription
            return
        }

        do {
            let dtos = try await session.api.send(
                APIRequest(
                    host: .agenda,
                    path: "/v1/matricola/\(matricola)/events",
                    query: [
                        .init(name: "start_date", value: PoliMiDate.queryString(startDate)),
                        .init(name: "end_date", value: PoliMiDate.queryString(endDate(from: startDate))),
                        .init(name: "n_events", value: String(pageSize)),
                    ]
                ),
                as: [AgendaEventDTO].self
            )

            // Drop entries with unparseable timestamps rather than guessing at
            // a date and showing a lecture on the wrong day.
            let parsed = dtos.compactMap { $0.toEvent() }
            if parsed.count < dtos.count {
                log.warning("Discarded \(dtos.count - parsed.count) agenda events with bad dates")
            }
            events = parsed.sorted { $0.start < $1.start }
            loadedFrom = startDate
        } catch {
            log.error("Agenda load failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            // No mock fallback: sample lectures shown as real would send
            // someone to a room that does not exist.
            events = []
        }
    }

    private func endDate(from start: Date) -> Date {
        PoliMiDate.romeCalendar.date(byAdding: window, to: start) ?? start
    }

    /// Events on a given day, in Rome time.
    func events(on day: Date) -> [AgendaEvent] {
        let calendar = PoliMiDate.romeCalendar
        return events
            .filter { calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// Days in the loaded window that actually have something on them, used to
    /// dot the week strip.
    func daysWithEvents() -> Set<Date> {
        let calendar = PoliMiDate.romeCalendar
        return Set(events.map { calendar.startOfDay(for: $0.start) })
    }

    /// The next event from now, for the Home screen summary.
    func nextEvent(after moment: Date = .now) -> AgendaEvent? {
        events.first { $0.end > moment }
    }
}
