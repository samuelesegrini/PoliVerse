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
@Suite("Agenda load", .tags(.network))
@MainActor
struct AgendaLoadTests {
    /// A matricola of each test's own. The model keeps an offline copy per
    /// matricola and restores it on the first load, so with one shared number a
    /// test read what another had just saved, and passed or failed by order.
    private let matricola = String(Int.random(in: 10_000_000...99_999_999))
    private var eventsPath: String { "/v1/matricola/\(matricola)/events" }
    private var deadlinesPath: String { "/v1/matricola/\(matricola)/events/deadlines" }

    /// Midday, so the ±window never straddles a day boundary by accident.
    private static let day = PoliMiDate.romeCalendar.date(
        from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!

    private func model(_ http: FixtureHTTP, signedIn: Bool = true,
                       isSample: Bool = false) -> AgendaModel {
        AgendaModel(account: StubAccount(matricola: signedIn ? matricola : nil, isSample: isSample, http: http))
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

    /// One deadline, `hours` from the fixed day, as the deadlines endpoint sends it.
    private static func deadlines(_ offsets: [Double], idFrom: Int = 100) -> Data {
        let rows = offsets.enumerated().map { index, hours -> String in
            let start = day.addingTimeInterval(hours * 3600)
            return """
            {"event_id": \(idFrom + index),
             "date_start": "\(wire.string(from: start))",
             "date_end": "\(wire.string(from: start))",
             "event_type": {"typeId": 4},
             "title": {"it": "Consegna \(idFrom + index)"}}
            """
        }
        return Data("[\(rows.joined(separator: ","))]".utf8)
    }

    // MARK: - The weeks asked for

    /// From the week of seven days before to the week of a month after: the
    /// official app asks for a month forward, and a week back costs nothing
    /// while meaning that stepping back a week does not trigger a round trip.
    /// Whole weeks, so a week is held or not, and in one request.
    @Test("The weeks from the one before to a month ahead go out in one request")
    func weeksAroundTheDay() async throws {
        let http = FixtureHTTP([eventsPath: Data("[]".utf8),
                                deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)

        await agenda.load(around: Self.day)

        let path = eventsPath
        let requests = await http.requests.filter { $0.path == path }
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.host == .agenda)
        let calendar = PoliMiDate.romeCalendar
        let start = try #require(request.query.first { $0.name == "start_date" }?.value)
        let end = try #require(request.query.first { $0.name == "end_date" }?.value)
        let firstWeek = AgendaWeeks.week(of: try #require(calendar.date(byAdding: .day, value: -7, to: Self.day)))
        let lastWeek = AgendaWeeks.week(of: try #require(calendar.date(byAdding: .month, value: 1, to: Self.day)))
        #expect(start == PoliMiDate.queryString(firstWeek))
        #expect(end == PoliMiDate.queryString(try #require(calendar.date(byAdding: .day, value: 7, to: lastWeek))))
    }

    /// Weeks start on Monday in Rome, and a run longer than a load ever asks
    /// for is split, so each request stays under the event cap.
    @Test("Contiguous weeks are grouped into runs of at most seven")
    func runs() throws {
        let calendar = PoliMiDate.romeCalendar
        let monday = AgendaWeeks.week(of: Self.day)
        #expect(calendar.component(.weekday, from: monday) == 2)
        let weeks = try (0..<8).map { try #require(calendar.date(byAdding: .day, value: 7 * $0, to: monday)) }
        let gap = try #require(calendar.date(byAdding: .day, value: 7 * 20, to: monday))
        let runs = AgendaWeeks.runs(weeks + [gap])
        #expect(runs.map(\.count) == [7, 1, 1])
        // However the month falls, a load around a date is one run.
        for offset in 0..<31 {
            let date = try #require(calendar.date(byAdding: .day, value: offset, to: Self.day))
            #expect(AgendaWeeks.runs(AgendaWeeks.weeks(around: date)).count == 1)
        }
    }

    /// Deadlines are sparse and worth seeing early, so they get their own
    /// horizon rather than the weeks on screen.
    @Test("Deadlines are fetched a year ahead, not over the weeks shown")
    func deadlinesLookFurther() async throws {
        let http = FixtureHTTP([eventsPath: Data("[]".utf8),
                                deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)

        await agenda.load(around: Self.day)

        let request = try #require(await http.requests.first { $0.path == deadlinesPath })
        let end = try #require(request.query.first { $0.name == "end_date" }?.value)
        let from = AgendaWeeks.week(of: try #require(PoliMiDate.romeCalendar.date(byAdding: .day, value: -7, to: Self.day)))
        #expect(end == PoliMiDate.queryString(
            try #require(PoliMiDate.romeCalendar.date(byAdding: .year, value: 1, to: from))))
    }

    // MARK: - Partial failure

    /// One endpoint being down is not the timetable being unavailable.
    @Test("Lectures still show when the deadlines endpoint is down")
    func lecturesSurviveDeadlineFailure() async {
        let http = FixtureHTTP([eventsPath: Self.events([2])],
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
            matricola: matricola,
            http: FixtureHTTP([eventsPath: Self.events([2, 5])],
                              fallback: .failure(APIError.badStatus(500, body: "down"))))
        let agenda = AgendaModel(account: account)
        await agenda.load(around: Self.day)
        #expect(agenda.events.count == 2)

        account.http = FixtureHTTP.failing(APIError.badStatus(500, body: "down"))
        await agenda.load(around: Self.day, force: true)

        #expect(agenda.events.count == 2)
    }

    /// The deadlines answering is not the timetable answering: taking their
    /// reply as the whole window emptied the week, and the widgets, the
    /// reminders and the Watch with it.
    @Test("Lectures down and deadlines up keeps the lectures held")
    func lecturesDownKeepsLectures() async {
        let account = StubAccount(
            matricola: matricola,
            http: FixtureHTTP([eventsPath: Self.events([2, 5]), deadlinesPath: Data("[]".utf8)]))
        let agenda = AgendaModel(account: account)
        await agenda.load(around: Self.day)

        account.http = FixtureHTTP([deadlinesPath: Self.deadlines([30])],
                                   fallback: .failure(APIError.badStatus(500, body: "down")))
        await agenda.load(around: Self.day, force: true)

        #expect(agenda.events(on: Self.day).filter { $0.kind != .deadline }.count == 2)
        #expect(agenda.errorMessage != nil)
    }

    /// The reverse: deadlines are fetched a year ahead and change rarely, so a
    /// failed fetch is no reason to forget the ones already known.
    @Test("Deadlines down keeps the deadlines held")
    func deadlinesDownKeepsDeadlines() async {
        let account = StubAccount(
            matricola: matricola,
            http: FixtureHTTP([eventsPath: Self.events([2]), deadlinesPath: Self.deadlines([30])]))
        let agenda = AgendaModel(account: account)
        await agenda.load(around: Self.day)
        #expect(agenda.milestones().count == 1)

        account.http = FixtureHTTP([eventsPath: Self.events([2])],
                                   fallback: .failure(APIError.badStatus(500, body: "down")))
        await agenda.load(around: Self.day, force: true)

        #expect(agenda.milestones().count == 1)
        #expect(agenda.errorMessage == nil)
    }

    /// A week whose lectures did not arrive is not held: marking it covered
    /// showed it as a free week and never asked again.
    @Test("A paged week whose lectures failed is fetched again")
    func failedPageIsRetried() async {
        let account = StubAccount(
            matricola: matricola,
            http: FixtureHTTP([eventsPath: Self.events([2]), deadlinesPath: Data("[]".utf8)]))
        let agenda = AgendaModel(account: account)
        await agenda.load(around: Self.day)

        let later = Self.day.addingTimeInterval(60 * 86_400)
        account.http = FixtureHTTP([deadlinesPath: Data("[]".utf8)],
                                   fallback: .failure(APIError.badStatus(500, body: "down")))
        await agenda.ensureLoaded(covering: later)
        #expect(agenda.events(on: later).isEmpty)

        account.http = FixtureHTTP([eventsPath: Self.events([60 * 24 + 2], idFrom: 10),
                                    deadlinesPath: Data("[]".utf8)])
        await agenda.ensureLoaded(covering: later)
        #expect(agenda.events(on: later).count == 1)
        #expect(agenda.events(on: Self.day).count == 1)
    }

    // MARK: - Grouping and the window held

    @Test("Events are grouped by Rome day and sorted within it")
    func groupsByDay() async {
        // Two the same day, one the next.
        let http = FixtureHTTP([eventsPath: Self.events([5, 2, 26]),
                                deadlinesPath: Data("[]".utf8)])
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
    @Test("A date in a week held does not refetch; one outside does")
    func refetchesOnlyOutsideTheWindow() async {
        let http = FixtureHTTP([eventsPath: Self.events([2]),
                                deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)
        await agenda.load(around: Self.day)
        let afterFirst = await http.requests.count

        await agenda.ensureLoaded(covering: Self.day.addingTimeInterval(86_400))
        #expect(await http.requests.count == afterFirst)

        // Two months out is past the month-ahead edge.
        await agenda.ensureLoaded(covering: Self.day.addingTimeInterval(60 * 86_400))
        #expect(await http.requests.count > afterFirst)
    }

    /// Paging waited on arrival: the week after the edge of what was held was
    /// fetched only once it was on screen, empty until the answer came.
    @Test("A date two weeks from the edge of the weeks held fetches ahead")
    func fetchesAheadNearTheEdge() async {
        let http = FixtureHTTP([eventsPath: Self.events([2]),
                                deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)
        await agenda.load(around: Self.day)
        let afterFirst = await http.requests.count

        // Held, but the week two after it is past the month ahead.
        let nearEdge = Self.day.addingTimeInterval(24 * 86_400)
        #expect(agenda.loadedRange?.contains(nearEdge) == true)
        await agenda.ensureLoaded(covering: nearEdge)
        #expect(await http.requests.count > afterFirst)
    }

    /// Hot or saving power, the weeks ahead can wait: only the one on screen is
    /// fetched.
    @Test("Under device pressure only the week asked for is fetched, not the weeks ahead")
    func noLookAheadUnderPressure() async {
        let http = FixtureHTTP([eventsPath: Self.events([2]),
                                deadlinesPath: Data("[]".utf8)])
        let agenda = AgendaModel(account: StubAccount(matricola: matricola, http: http),
                                 pressure: { true })
        await agenda.load(around: Self.day)
        let afterFirst = await http.requests.count

        let nearEdge = Self.day.addingTimeInterval(24 * 86_400)
        await agenda.ensureLoaded(covering: nearEdge)
        #expect(await http.requests.count == afterFirst)
    }

    /// A launch a few minutes after the last fetched the timetable again, though
    /// every week was on disk as fetched.
    @Test("A new model within the weeks' lifetime serves them from disk without fetching")
    func keptWeeksAreServed() async {
        let http = FixtureHTTP([eventsPath: Self.events([2]),
                                deadlinesPath: Data("[]".utf8)])
        await model(http).load(around: Self.day)
        await OfflineStore.shared.flushed()
        let afterFirst = await http.requests.count

        let relaunched = model(http)
        await relaunched.load(around: Self.day)
        #expect(await http.requests.count == afterFirst)
        #expect(relaunched.events(on: Self.day).count == 1)
    }

    /// Paging the calendar past the held month used to replace the window, and
    /// today's lectures left the widgets, the reminders and the Watch with it.
    @Test("Navigating past the weeks held adds to them instead of replacing them")
    func pagingKeepsToday() async {
        let account = StubAccount(
            matricola: matricola,
            http: FixtureHTTP([eventsPath: Self.events([2]), deadlinesPath: Data("[]".utf8)]))
        let agenda = AgendaModel(account: account)
        await agenda.load(around: Self.day)

        let later = Self.day.addingTimeInterval(60 * 86_400)
        account.http = FixtureHTTP([eventsPath: Self.events([60 * 24 + 2], idFrom: 10),
                                    deadlinesPath: Data("[]".utf8)])
        await agenda.ensureLoaded(covering: later)

        #expect(agenda.events(on: Self.day).count == 1)
        #expect(agenda.events(on: later).count == 1)

        // Both spans are held: going back does not fetch again.
        account.http = FixtureHTTP.failing(APIError.badStatus(500, body: "down"))
        await agenda.ensureLoaded(covering: Self.day)
        #expect(agenda.errorMessage == nil)
    }

    /// The launch refresh and a paged week meet often: the calendar opens while
    /// the refresh is still waiting on the network.
    @Test("A week asked for during another load is fetched once that load ends")
    func pagingDuringALoadIsNotDropped() async {
        let http = FixtureHTTP([eventsPath: Self.events([2]), deadlinesPath: Data("[]".utf8)])
        let agenda = model(http)
        let later = Self.day.addingTimeInterval(60 * 86_400)

        async let refresh: Void = agenda.load(around: Self.day)
        async let paged: Void = agenda.ensureLoaded(covering: later)
        _ = await (refresh, paged)

        let path = eventsPath
        let requests = await http.requests
        let lectureFetches = requests.filter { $0.path == path }
        #expect(lectureFetches.count == 2)
        #expect(!agenda.isLoading)
    }

    @Test("The next event is the first that has not ended")
    func nextEventSkipsWhatIsOver() async throws {
        let http = FixtureHTTP([eventsPath: Self.events([-2, 3]),
                                deadlinesPath: Data("[]".utf8)])
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
        let agenda = model(http, signedIn: false)

        await agenda.load(around: Self.day)

        #expect(await http.requests.isEmpty)
        #expect(agenda.errorMessage != nil)
    }
}
