import Foundation
import Testing
@testable import PoliVerse

/// The timetable's load, which had no test of any kind: the model took a
/// ``Session``, so exercising it meant standing up the Keychain, the service
/// directory and an API client.
///
/// It is the most-opened screen in the app, and the rules below — which window
/// is fetched, what happens when one of the two endpoints is down, what is kept
/// when both are — are the ones a student notices when they are wrong.
@Suite("Agenda load")
@MainActor
struct AgendaLoadTests {
    private static let matricola = "111"
    private static let eventsPath = "/v1/matricola/111/events"
    private static let deadlinesPath = "/v1/matricola/111/events/deadlines"

    /// Midday, so the ±window never straddles a day boundary by accident.
    private static let day = PoliMiDate.romeCalendar.date(
        from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!

    private func model(_ http: FixtureHTTP, matricola: String? = matricola,
                       isSample: Bool = false) -> AgendaModel {
        AgendaModel(account: StubAccount(matricola: matricola, isSample: isSample, http: http))
    }

    /// The wire format the agenda sends: Rome wall-clock, no offset.
    private static let wire: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// One event, `hours` from the fixed day.
    private static func events(_ offsets: [Double], idFrom: Int = 1) -> Data {
        let rows = offsets.enumerated().map { index, hours -> String in
            let start = day.addingTimeInterval(hours * 3600)
            let end = start.addingTimeInterval(3600)
            return """
            {"event_id": \(idFrom + index),
             "date_start": "\(wire.string(from: start))",
             "date_end": "\(wire.string(from: end))",
             "title": {"it": "Lezione \(idFrom + index)"}}
            """
        }
        return Data("[\(rows.joined(separator: ","))]".utf8)
    }

    // MARK: - The window asked for

    /// A week behind and a month ahead: the official app asks for a month
    /// forward, and a week back costs nothing while meaning that stepping back
    /// a week does not trigger a round trip.
    @Test("The fetched window is a week behind and a month ahead")
    func windowAroundTheDay() async throws {
        let http = FixtureHTTP([Self.eventsPath: Data("[]".utf8),
                                Self.deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)

        await agenda.load(around: Self.day)

        let request = try #require(await http.requests.first { $0.path == Self.eventsPath })
        #expect(request.host == .agenda)
        let calendar = PoliMiDate.romeCalendar
        let start = try #require(request.query.first { $0.name == "start_date" }?.value)
        let end = try #require(request.query.first { $0.name == "end_date" }?.value)
        #expect(start == PoliMiDate.queryString(
            try #require(calendar.date(byAdding: .day, value: -7, to: Self.day))))
        #expect(end == PoliMiDate.queryString(
            try #require(calendar.date(byAdding: .month, value: 1, to: Self.day))))
    }

    /// Deadlines are sparse and worth seeing early, so they get their own
    /// horizon rather than the window on screen.
    @Test("Deadlines are fetched a year ahead, not over the shown window")
    func deadlinesLookFurther() async throws {
        let http = FixtureHTTP([Self.eventsPath: Data("[]".utf8),
                                Self.deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)

        await agenda.load(around: Self.day)

        let request = try #require(await http.requests.first { $0.path == Self.deadlinesPath })
        let end = try #require(request.query.first { $0.name == "end_date" }?.value)
        let from = try #require(PoliMiDate.romeCalendar.date(byAdding: .day, value: -7, to: Self.day))
        #expect(end == PoliMiDate.queryString(
            try #require(PoliMiDate.romeCalendar.date(byAdding: .year, value: 1, to: from))))
    }

    // MARK: - Partial failure

    /// One endpoint being down is not the timetable being unavailable.
    @Test("Lectures still show when the deadlines endpoint is down")
    func lecturesSurviveDeadlineFailure() async {
        let http = FixtureHTTP([Self.eventsPath: Self.events([2])],
                               fallback: .failure(APIError.badStatus(500, body: "down")))
        let agenda = model(http)

        await agenda.load(around: Self.day)

        #expect(agenda.events.count == 1)
        #expect(agenda.errorMessage == nil)
    }

    /// An empty calendar is indistinguishable from a free week, so what was
    /// held is kept rather than cleared — and never replaced with sample
    /// lectures, which would send someone to a room that does not exist.
    @Test("Both endpoints down keeps what was already on screen")
    func bothDownKeepsWhatIsHeld() async {
        let account = StubAccount(
            matricola: Self.matricola,
            http: FixtureHTTP([Self.eventsPath: Self.events([2, 5])],
                              fallback: .failure(APIError.badStatus(500, body: "down"))))
        let agenda = AgendaModel(account: account)
        await agenda.load(around: Self.day)
        #expect(agenda.events.count == 2)

        account.http = FixtureHTTP.failing(APIError.badStatus(500, body: "down"))
        await agenda.load(around: Self.day, force: true)

        #expect(agenda.events.count == 2)
    }

    // MARK: - Grouping and the window held

    @Test("Events are grouped by Rome day and sorted within it")
    func groupsByDay() async {
        // Two the same day, one the next.
        let http = FixtureHTTP([Self.eventsPath: Self.events([5, 2, 26]),
                                Self.deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)

        await agenda.load(around: Self.day)

        let today = agenda.events(on: Self.day)
        #expect(today.count == 2)
        #expect(today.map(\.start) == today.map(\.start).sorted())
        #expect(agenda.events(on: Self.day.addingTimeInterval(86_400)).count == 1)
        #expect(agenda.daysWithEvents().count == 2)
    }

    /// The reason the window is held at all: navigating inside it must not
    /// refetch, and stepping outside it must.
    @Test("A date inside the loaded window does not refetch; outside does")
    func refetchesOnlyOutsideTheWindow() async {
        let http = FixtureHTTP([Self.eventsPath: Self.events([2]),
                                Self.deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)
        await agenda.load(around: Self.day)
        let afterFirst = await http.requests.count

        await agenda.ensureLoaded(covering: Self.day.addingTimeInterval(86_400))
        #expect(await http.requests.count == afterFirst)

        // Two months out is past the month-ahead edge.
        await agenda.ensureLoaded(covering: Self.day.addingTimeInterval(60 * 86_400))
        #expect(await http.requests.count > afterFirst)
    }

    @Test("The next event is the first that has not ended")
    func nextEventSkipsWhatIsOver() async throws {
        let http = FixtureHTTP([Self.eventsPath: Self.events([-2, 3]),
                                Self.deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)
        await agenda.load(around: Self.day)

        let next = try #require(agenda.nextEvent(after: Self.day))
        #expect(next.end > Self.day)
    }

    // MARK: - Sample data and signing out

    @Test("Sample data is served without touching the network")
    func sampleBranch() async {
        let http = FixtureHTTP()
        let agenda = model(http, isSample: true)

        await agenda.load(around: Self.day)

        #expect(!agenda.events.isEmpty)
        #expect(await http.requests.isEmpty)
    }

    @Test("With no account, nothing is fetched and the reason is said")
    func signedOutSaysSo() async {
        let http = FixtureHTTP()
        let agenda = model(http, matricola: nil)

        await agenda.load(around: Self.day)

        #expect(await http.requests.isEmpty)
        #expect(agenda.errorMessage != nil)
    }
}
