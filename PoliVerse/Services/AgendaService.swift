import Foundation
import Observation
import OSLog

/// Lectures, exams and deadlines from the agenda endpoint.
///
/// `GET /agenda/api/me/{matricola}/events?start_date=yyyy-MM-dd&n_events=N`
///
/// The endpoint is count-based, not range-based: it returns the next `n_events`
/// items from `start_date` with no end date, so asking for "this week" means
/// over-fetching and filtering client-side. PoliFemo requests 200 and does the
/// same.
@Observable
final class AgendaService {
    private(set) var events: [AgendaEvent] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Start of the window currently held, so we know when a scroll needs more.
    private(set) var loadedFrom: Date?

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "agenda")

    /// Matches PoliFemo's page size. Large enough for several weeks of a full
    /// timetable, small enough to stay a quick request.
    private let pageSize = 200

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
                    host: .app,
                    path: "/agenda/api/me/\(matricola)/events",
                    query: [
                        .init(name: "start_date", value: PoliMiDate.queryString(startDate)),
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
