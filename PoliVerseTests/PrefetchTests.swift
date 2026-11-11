import Foundation
import Synchronization
import Testing
@testable import PoliVerse

/// Preparing ahead of the student: the budget that says whether a speculative
/// request may go, the lanes of the gate that keep it behind the screen, and the
/// timetable rule that says what the next lecture needs. Test names carry the id
/// of the requirement they check (docs/rasd).
@Suite("Preparazione in anticipo: budget e regola dell’orario")
struct SpeculativeBudgetTests {
    private typealias Budget = SpeculativeBudget

    @Test("R30: niente in anticipo con Dati ridotti, né sulla rete cellulare se non è permesso")
    func test_R30_lowDataAndMeteredNetwork() {
        let settings = Budget.Settings()
        #expect(Budget.allows(5, device: .init(lowData: true), settings: settings, sentToday: 0) == 0)
        #expect(Budget.refusal(device: .init(metered: true), settings: settings, sentToday: 0) == .metered)
        var allowed = settings
        allowed.allowMetered = true
        #expect(Budget.allows(5, device: .init(metered: true), settings: allowed, sentToday: 0) == 5)
        // Low Data Mode wins even when cellular is allowed.
        #expect(Budget.refusal(device: .init(lowData: true, metered: true), settings: allowed, sentToday: 0) == .lowData)
    }

    @Test("R31: niente in anticipo con il Risparmio energetico o il telefono caldo")
    func test_R31_lowPowerAndHeat() {
        let settings = Budget.Settings()
        #expect(Budget.refusal(device: .init(lowPower: true), settings: settings, sentToday: 0) == .lowPower)
        #expect(Budget.refusal(device: .init(thermal: .serious), settings: settings, sentToday: 0) == .hot)
        #expect(Budget.refusal(device: .init(thermal: .critical), settings: settings, sentToday: 0) == .hot)
        #expect(Budget.refusal(device: .init(thermal: .fair), settings: settings, sentToday: 0) == nil)
    }

    @Test("R33: al massimo 600 al giorno, e ciò che resta della giornata")
    func test_R33_dailyLimit() {
        let device = Budget.Device()
        let settings = Budget.Settings()
        #expect(settings.dailyLimit == 600)
        #expect(Budget.allows(10, device: device, settings: settings, sentToday: 595) == 5)
        #expect(Budget.allows(10, device: device, settings: settings, sentToday: 600) == 0)
        #expect(Budget.refusal(device: device, settings: settings, sentToday: 600) == .limitReached)
    }

    @Test("Spento dallo studente: niente in anticipo")
    func test_switchedOff() {
        var settings = Budget.Settings()
        settings.enabled = false
        #expect(Budget.refusal(device: .init(), settings: settings, sentToday: 0) == .off)
    }

    @Test("R33: il conteggio ricomincia ogni giorno, a Roma")
    func test_R33_countStartsAgainEachDay() {
        let morning = PoliMiDate.time(9, on: Date(timeIntervalSince1970: 1_772_000_000))
        let stored = SpeculativeCount(day: PoliMiDate.queryString(morning), sent: 42)
        #expect(SpeculativeCount.today(at: morning.addingTimeInterval(3600), stored: stored).sent == 42)
        #expect(SpeculativeCount.today(at: morning.addingTimeInterval(86_400), stored: stored).sent == 0)
        #expect(SpeculativeCount.today(at: morning, stored: nil).sent == 0)
    }

    // MARK: - R19: what the next lecture needs

    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func entry(_ id: Int, inMinutes minutes: Double, title: String = "Fisica", room: String? = "B.3.2",
                       kind: EventKind = .lecture) -> AgendaEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return AgendaEvent(id: id, title: title, start: start, end: start.addingTimeInterval(5400),
                           kind: kind, room: room.map { "Aula \($0)" }, roomAcronym: room)
    }

    @Test("R19: le lezioni dell’ora che viene: l’aula e il corso, la più vicina prima")
    func test_R19_lecturesOfTheNextHour() {
        let lectures = [
            entry(1, inMinutes: 50, title: "Analisi", room: "3.0.1"),
            entry(2, inMinutes: 20),
            entry(3, inMinutes: 90, title: "Chimica"),          // too far
            entry(4, inMinutes: -10, title: "Algebra"),          // already begun
            entry(5, inMinutes: 30, title: "Consegna", kind: .deadline),
        ]
        let day = PoliMiDate.romeCalendar.startOfDay(for: now)
        #expect(TimetablePrefetch.wanted(now: now, lectures: lectures) == [
            .room(names: ["B.3.2", "Aula B.3.2"], day: day), .course(title: "Fisica"),
            .room(names: ["3.0.1", "Aula 3.0.1"], day: day), .course(title: "Analisi"),
        ])
    }

    @Test("R19: due lezioni nella stessa aula o dello stesso corso si preparano una volta")
    func test_R19_eachThingOnce() {
        let lectures = [entry(1, inMinutes: 10), entry(2, inMinutes: 40), entry(3, inMinutes: 45, room: nil)]
        let items = TimetablePrefetch.wanted(now: now, lectures: lectures)
        #expect(items.count == 2)
        #expect(TimetablePrefetch.wanted(now: now, lectures: []).isEmpty)
    }

    @Test("R33: si prepara ciò che sta nel budget, nell’ordine")
    func test_R33_whatFitsTheAllowance() {
        let day = PoliMiDate.romeCalendar.startOfDay(for: now)
        let items: [PrefetchItem] = [.room(names: ["A"], day: day), .course(title: "A"),
                                     .room(names: ["B"], day: day), .course(title: "B")]
        #expect(TimetablePrefetch.fitting(items, allowance: 10) == items)
        // The second room does not fit; the course after it still does.
        #expect(TimetablePrefetch.fitting(items, allowance: 6) == [items[0], items[1], items[3]])
        #expect(TimetablePrefetch.fitting(items, allowance: 0).isEmpty)
    }
}

/// The two lanes of the gate, with a phone and settings the test sets.
@Suite("Varco: corsie", .tags(.timing))
struct RequestLanesTests {
    /// What the test lets the requests do.
    private nonisolated final class Bench: Sendable {
        let running = Mutex(0)
        let most = Mutex(0)
        let open = Mutex(false)
        let device = Mutex(SpeculativeBudget.Device())
        let settings = Mutex(SpeculativeBudget.Settings())

        func enter() {
            running.withLock { $0 += 1 }
            let now = running.withLock { $0 }
            most.withLock { $0 = max($0, now) }
        }
        func leave() { running.withLock { $0 -= 1 } }
    }

    private func gate(_ bench: Bench) -> RequestGate {
        RequestGate(ledger: LoadingLedger(file: nil),
                    device: { bench.device.withLock { $0 } },
                    settings: { bench.settings.withLock { $0 } },
                    counts: .memory())
    }

    /// A request in flight, whose outcome is read without awaiting its task:
    /// awaiting raises the task to the test's priority, which is what puts a
    /// joined warm-up in the screen's lane.
    private nonisolated final class Request: Sendable {
        let task = Mutex<Task<Void, Never>?>(nil)
        let result = Mutex<Result<Int, any Error>?>(nil)

        /// How it ended, once it has.
        var value: Int {
            get async throws {
                while true {
                    if let ended = result.withLock({ $0 }) { return try ended.get() }
                    try? await Task.sleep(for: .milliseconds(2))
                }
            }
        }

        func cancel() { task.withLock { $0 }?.cancel() }
    }

    /// A request that holds until the bench opens.
    private func held(_ gate: RequestGate, _ bench: Bench, host: String = "maps",
                      speculative: Bool, priority: TaskPriority = .utility) -> Request {
        let request = Request()
        let task = Task.detached(priority: priority) {
            let outcome: Result<Int, any Error>
            do {
                outcome = .success(try await LoadContext.$current.withValue(.init(part: "test", speculative: speculative)) {
                    try await gate.run(host: host) { () async throws -> Int in
                        bench.enter()
                        defer { bench.leave() }
                        while !bench.open.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(2)) }
                        return 1
                    }
                })
            } catch {
                outcome = .failure(error)
            }
            request.result.withLock { $0 = outcome }
        }
        request.task.withLock { $0 = task }
        return request
    }

    private func until(_ condition: () async -> Bool) async {
        for _ in 0..<1000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("R32: al massimo due richieste in anticipo per servizio alla volta")
    func test_R32_twoAtATimePerHost() async throws {
        let bench = Bench()
        let gate = gate(bench)
        let tasks = (0..<5).map { _ in held(gate, bench, speculative: true) }
        await until { await gate.speculativeLoad("maps") == (2, 3) }
        #expect(await gate.speculativeLoad("maps") == (2, 3))
        // Another host has its own two.
        let other = held(gate, bench, host: "iae", speculative: true)
        await until { await gate.speculativeLoad("iae").running == 1 }

        bench.open.withLock { $0 = true }
        for task in tasks + [other] { _ = try await task.value }
        #expect(bench.most.withLock { $0 } <= 3)
        #expect(await gate.speculativeLoad("maps") == (0, 0))
        #expect(await gate.sentToday() == 6)
    }

    @Test("R32: ciò che è a schermo passa subito, ciò che è in anticipo aspetta che finisca")
    func test_R32_screenGoesFirst() async throws {
        let bench = Bench()
        let gate = gate(bench)
        let screen = held(gate, bench, speculative: false, priority: .userInitiated)
        await until { bench.running.withLock { $0 } == 1 }

        let ahead = held(gate, bench, speculative: true)
        await until { await gate.speculativeLoad("maps").waiting == 1 }
        #expect(await gate.speculativeLoad("maps") == (0, 1))
        // Another request for the screen does not wait behind it.
        let second = Task(priority: .userInitiated) { try await gate.run(host: "maps") { 2 } }
        #expect(try await second.value == 2)

        bench.open.withLock { $0 = true }
        _ = try await screen.value
        _ = try await ahead.value
        #expect(await gate.sentToday() == 1)
    }

    @Test("R32: un anticipo che qualcuno aspetta è nella corsia dello schermo")
    func test_R32_joinedWarmUpIsForTheScreen() async throws {
        let bench = Bench()
        bench.open.withLock { $0 = true }
        let gate = gate(bench)
        _ = try await held(gate, bench, speculative: true, priority: .userInitiated).value
        #expect(await gate.sentToday() == 0)
    }

    @Test("R30, R31: con il telefono che non lo permette la richiesta in anticipo non parte, quella a schermo sì")
    func test_R30_R31_refusedButScreenGoes() async throws {
        let bench = Bench()
        bench.open.withLock { $0 = true }
        bench.device.withLock { $0.lowData = true }
        let gate = gate(bench)

        await #expect(throws: SpeculationRefused(reason: .lowData)) {
            _ = try await held(gate, bench, speculative: true).value
        }
        bench.device.withLock { $0 = .init(lowPower: true) }
        await #expect(throws: SpeculationRefused(reason: .lowPower)) {
            _ = try await held(gate, bench, speculative: true).value
        }
        #expect(try await held(gate, bench, speculative: false).value == 1)
        #expect(bench.most.withLock { $0 } == 1)
        #expect(await gate.sentToday() == 0)
    }

    @Test("R33: raggiunto il limite del giorno non parte più niente in anticipo")
    func test_R33_limitStopsSpeculation() async throws {
        let bench = Bench()
        bench.open.withLock { $0 = true }
        bench.settings.withLock { $0.dailyLimit = 3 }
        let gate = gate(bench)
        for _ in 0..<3 { _ = try await held(gate, bench, speculative: true).value }
        #expect(await gate.sentToday() == 3)
        #expect(await gate.allowance(for: 4) == 0)
        await #expect(throws: SpeculationRefused(reason: .limitReached)) {
            _ = try await held(gate, bench, speculative: true).value
        }
        #expect(await gate.sentToday() == 3)
    }

    @Test("R33: chi aspetta il suo turno è fermato se nel frattempo il limite è raggiunto")
    func test_R33_waitingRequestIsStoppedAtTheLimit() async throws {
        let bench = Bench()
        bench.settings.withLock { $0.dailyLimit = 3 }
        let gate = gate(bench)
        let first = held(gate, bench, speculative: true)
        let second = held(gate, bench, speculative: true)
        await until { await gate.speculativeLoad("maps").running == 2 }
        let third = held(gate, bench, speculative: true)
        await until { await gate.speculativeLoad("maps").waiting == 1 }
        #expect(await gate.speculativeLoad("maps") == (2, 1))
        // Another host takes the last request of the day meanwhile.
        let elsewhere = held(gate, bench, host: "iae", speculative: true)
        await until { await gate.sentToday() == 3 }
        _ = elsewhere

        bench.open.withLock { $0 = true }
        _ = try await first.value
        _ = try await second.value
        await #expect(throws: SpeculationRefused(reason: .limitReached)) { _ = try await third.value }
    }

    @Test("R32: chi aspetta e se ne va libera il posto")
    func test_R32_cancelledWhileWaiting() async throws {
        let bench = Bench()
        let gate = gate(bench)
        let running = [held(gate, bench, speculative: true), held(gate, bench, speculative: true)]
        await until { await gate.speculativeLoad("maps").running == 2 }
        let leaving = held(gate, bench, speculative: true)
        await until { await gate.speculativeLoad("maps").waiting == 1 }
        leaving.cancel()
        await until { await gate.speculativeLoad("maps").waiting == 0 }
        #expect(await gate.speculativeLoad("maps") == (2, 0))
        await #expect(throws: CancellationError.self) { _ = try await leaving.value }

        bench.open.withLock { $0 = true }
        for task in running { _ = try await task.value }
        #expect(await gate.sentToday() == 2)
    }
}

/// The runner, with the warming and the budget the test sets.
@Suite("Preparazione prima della lezione")
@MainActor
struct LecturePrefetchTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    private final class Log {
        var rooms: [[String]] = []
        var courses: [String] = []
        var asked: [Int] = []
    }

    private func lecture(_ id: Int, inMinutes minutes: Double, title: String, room: String) -> AgendaEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return AgendaEvent(id: id, title: title, start: start, end: start.addingTimeInterval(5400),
                           kind: .lecture, roomAcronym: room)
    }

    private func runner(_ log: Log, lectures: [AgendaEvent], allowance: Int) -> LecturePrefetch {
        LecturePrefetch(lectures: { lectures },
                        room: { names, _ in log.rooms.append(names) },
                        course: { log.courses.append($0) },
                        allowance: { log.asked.append($0); return min($0, allowance) })
    }

    @Test("R19: un’ora prima della lezione si preparano l’aula e il corso")
    func test_R19_roomAndCourseBeforeTheLecture() async {
        let log = Log()
        let lectures = [lecture(1, inMinutes: 40, title: "Fisica", room: "B.3.2"),
                        lecture(2, inMinutes: 200, title: "Chimica", room: "3.0.1")]
        let items = await runner(log, lectures: lectures, allowance: 600).run(now: now)
        #expect(items.count == 2)
        #expect(log.rooms == [["B.3.2"]])
        #expect(log.courses == ["Fisica"])
        #expect(log.asked == [5])
    }

    @Test("R19, R33: niente da preparare non chiede il budget; senza budget non si prepara niente")
    func test_R19_R33_nothingWantedOrNothingAllowed() async {
        let log = Log()
        #expect(await runner(log, lectures: [], allowance: 600).run(now: now).isEmpty)
        #expect(log.asked.isEmpty)

        let lectures = [lecture(1, inMinutes: 40, title: "Fisica", room: "B.3.2")]
        #expect(await runner(log, lectures: lectures, allowance: 0).run(now: now).isEmpty)
        #expect(log.rooms.isEmpty && log.courses.isEmpty)

        // Room for the course page alone.
        #expect(await runner(log, lectures: lectures, allowance: 1).run(now: now) == [.course(title: "Fisica")])
    }
}
