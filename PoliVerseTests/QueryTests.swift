import Foundation
import Observation
import Testing
@testable import PoliVerse

/// The pipeline every service used to write for itself.
///
/// Worth stating what these tests are evidence *of*, beyond the assertions.
/// Before the shared pipeline — ``Query`` over a ``Loader``, first called
/// `Store` — there was no way to exercise a service's load at all: every
/// model built its own `URLSession` and took a `Session`, whose initialiser
/// stands up the Keychain, the service directory, an API client and the login
/// flow. So the load path — the window, the offline copy, the sample branch,
/// what survives a failure — was the least tested code in the app despite being
/// the code every screen depends on. One `Account` and one `HTTP` is the whole
/// price of getting at it.
@Suite("Query")
@MainActor
struct QueryTests {
    private nonisolated struct Payload: Codable, Equatable, Sendable {
        var text: String
    }

    /// A source with no endpoint behind it: the fixture decides what `fetch`
    /// sees, and a counter records how often it was actually called, which is
    /// the only way to tell a suppressed load from a fast one.
    private nonisolated struct Probe: Resource {
        static let id = "probe"
        static let ttl: TimeInterval = 300

        let calls = Counter()

        @concurrent
        func fetch(_ key: Whole, env: Env, previous: Payload?) async throws -> Payload {
            await calls.increment()
            let data = try await env.http.data(for: APIRequest(host: .app, path: "/probe"))
            return try JSONDecoder().decode(Payload.self, from: data)
        }

        func sample(_ key: Whole) -> Payload? { Payload(text: "sample") }
    }

    private actor Counter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    private static func body(_ text: String) -> Data {
        try! JSONEncoder().encode(Payload(text: text))
    }

    private func offline() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("A load fetches, keeps the value and reports idle")
    func fetches() async {
        let http = FixtureHTTP(["/probe": Self.body("fresh")])
        let store = Query(Probe(), account: StubAccount(http: http), offline: offline())

        await store.load()

        #expect(store.value == Payload(text: "fresh"))
        #expect(store.phase == .idle)
        #expect(store.errorMessage == nil)
    }

    /// The reason a fresh value is served without asking: SwiftUI re-fires `.task` on every
    /// return to a tab, and three services refetching per tab switch was
    /// visible in the log on a real account.
    @Test("A second load inside the window does not reach the network")
    func suppressesRefetch() async {
        let probe = Probe()
        let http = FixtureHTTP(["/probe": Self.body("fresh")])
        let store = Query(probe, account: StubAccount(http: http), offline: offline())

        await store.load()
        await store.load()

        #expect(await probe.calls.count == 1)
    }

    /// Pull-to-refresh has to work however recent the last load was.
    @Test("A forced load always reaches the network")
    func forceBypassesWindow() async {
        let probe = Probe()
        let http = FixtureHTTP(["/probe": Self.body("fresh")])
        let store = Query(probe, account: StubAccount(http: http), offline: offline())

        await store.load()
        await store.load(force: true)

        #expect(await probe.calls.count == 2)
    }

    /// Flipping "Usa dati di esempio", or switching enrolment, changes what the
    /// held data *describes* — so it must reload however recent it is.
    @Test("A changed account reloads inside the window")
    func accountChangeReloads() async {
        let probe = Probe()
        let http = FixtureHTTP(["/probe": Self.body("fresh")])
        let account = StubAccount(matricola: "111", http: http)
        let store = Query(probe, account: account, offline: offline())

        await store.load()
        account.matricola = "222"
        await store.load()

        #expect(await probe.calls.count == 2)
    }

    /// The behaviour ``CareerModel`` had and `RoomsModel` did not. Losing
    /// signal must not replace a student's record with a blank screen.
    @Test("A failed load keeps the last good value and says what went wrong")
    func failureKeepsValue() async {
        let account = StubAccount(http: FixtureHTTP(["/probe": Self.body("fresh")]))
        let store = Query(Probe(), account: account, offline: offline())
        await store.load()

        account.http = FixtureHTTP.failing(APIError.badStatus(500, body: "nope"))
        await store.load(force: true)

        #expect(store.value == Payload(text: "fresh"))
        #expect(store.errorMessage != nil)
    }

    /// A failed load must not count as fresh, or one bad moment serves an
    /// error for the next five minutes.
    @Test("A failed load retries on the next appearance")
    func failureDoesNotMarkWindow() async {
        let probe = Probe()
        let http = FixtureHTTP.failing(APIError.badStatus(500, body: "nope"))
        let store = Query(probe, account: StubAccount(http: http), offline: offline())

        await store.load()
        await store.load()

        #expect(await probe.calls.count == 2)
    }

    /// A request abandoned because its view went away is not a failure, and was
    /// surfacing as "Impossibile raggiungere i server del Politecnico" to
    /// anyone who left a tab mid-load.
    @Test("A cancelled request is not reported to the student")
    func cancellationIsSilent() async {
        let http = FixtureHTTP.failing(APIError.cancelled)
        let store = Query(Probe(), account: StubAccount(http: http), offline: offline())

        await store.load()

        #expect(store.errorMessage == nil)
        #expect(store.phase == .idle)
    }

    /// Sample data is a substitution made once, not a branch every screen has
    /// to remember.
    @Test("Sample data is served without touching the network")
    func sampleBranch() async {
        let probe = Probe()
        let http = FixtureHTTP()
        let store = Query(probe, account: StubAccount(isSample: true, http: http),
                          offline: offline())

        await store.load()

        #expect(store.value == Payload(text: "sample"))
        #expect(await probe.calls.count == 0)
    }

    /// Sample data is invented, so it must never be written to a real
    /// student's offline copy.
    @Test("Sample data is never written to the offline copy")
    func sampleIsNotPersisted() async {
        let offline = offline()
        let account = StubAccount(matricola: "111", isSample: true, http: FixtureHTTP())
        let store = Query(Probe(), account: account, offline: offline)

        await store.load()
        offline.flush()

        #expect(offline.load(Payload.self, as: Probe.id, account: "111") == nil)
    }

    /// The app opens with content instead of a spinner.
    @Test("The offline copy is restored before the fetch lands")
    func restoresOfflineCopy() async {
        let offline = offline()
        offline.save(Payload(text: "cached"), as: Probe.id, account: "111")
        let http = FixtureHTTP.failing(APIError.badStatus(500, body: "nope"))
        let store = Query(Probe(), account: StubAccount(matricola: "111", http: http),
                          offline: offline)

        await store.load()

        // The fetch failed, so what is on screen is what was on disk — and it
        // is stamped with an age rather than passed off as fresh.
        #expect(store.value == Payload(text: "cached"))
        #expect(store.age != nil)
    }

    @Test("A successful load writes the offline copy")
    func savesOfflineCopy() async {
        let offline = offline()
        let http = FixtureHTTP(["/probe": Self.body("fresh")])
        let store = Query(Probe(), account: StubAccount(matricola: "111", http: http),
                          offline: offline)

        await store.load()
        offline.flush()

        #expect(offline.load(Payload.self, as: Probe.id, account: "111")?.value
            == Payload(text: "fresh"))
    }

    /// Signing out must not leave the previous student's record on disk under
    /// a nil account — ``OfflineStore`` refuses it, and the query must not
    /// pretend otherwise by stamping an age.
    @Test("With no account, nothing is cached and no age is claimed")
    func anonymousCachesNothing() async {
        let http = FixtureHTTP(["/probe": Self.body("fresh")])
        let store = Query(Probe(), account: StubAccount(matricola: nil, http: http),
                          offline: offline())

        await store.load()

        #expect(store.value == Payload(text: "fresh"))
        #expect(store.age == nil)
    }

    /// Pull-to-refresh during the launch refresh used to return at once, so
    /// the spinner ended before any data arrived.
    @Test("A load asked for while one is in flight waits for it instead of returning")
    func secondCallerJoins() async {
        let gate = Gate()
        let store = Query(Gated(gate: gate), account: StubAccount(http: FixtureHTTP()), offline: offline())

        let first = Task { await store.load() }
        await gate.arrival()
        let secondDone = Flag()
        let second = Task {
            await store.load(force: true)
            secondDone.value = true
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!secondDone.value)

        await gate.open()
        await second.value
        await first.value
        #expect(store.value == Payload(text: "gated"))
        #expect(await gate.fetches == 1)
    }

    /// Two screens asking for one key through one loader cost one request.
    @Test("Two queries sharing a loader share its fetch")
    func sharedLoader() async {
        let probe = Probe()
        let account = StubAccount(http: FixtureHTTP(["/probe": Self.body("fresh")]))
        let loader = Loader(probe, offline: offline())
        let one = Query(probe, key: Whole(), account: account, loader: loader)
        let two = Query(probe, key: Whole(), account: account, loader: loader)

        await one.load()
        await two.load()

        #expect(two.value == Payload(text: "fresh"))
        #expect(await probe.calls.count == 1)
    }

    /// A value that did not change is not assigned again: every assignment to
    /// an observed property redraws whatever read it.
    @Test("A refetch with the same value leaves the value untouched")
    func unchangedValueIsNotReassigned() async {
        let http = FixtureHTTP(["/probe": Self.body("fresh")])
        let store = Query(Probe(), account: StubAccount(http: http), offline: offline())
        await store.load()

        let notified = Flag()
        withObservationTracking { _ = store.value } onChange: { notified.value = true }
        await store.load(force: true)

        #expect(!notified.value)
    }

    /// A flag set from a closure the compiler treats as concurrent.
    private nonisolated final class Flag: @unchecked Sendable {
        var value = false
    }

    /// A fetch that waits until the test lets it finish.
    private nonisolated struct Gated: Resource {
        static let id = "gated"
        let gate: Gate

        @concurrent
        func fetch(_ key: Whole, env: Env, previous: Payload?) async throws -> Payload {
            await gate.pass()
            return Payload(text: "gated")
        }

        func sample(_ key: Whole) -> Payload? { Payload(text: "sample") }
    }

    private actor Gate {
        private(set) var fetches = 0
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var arrivals: [CheckedContinuation<Void, Never>] = []

        func pass() async {
            fetches += 1
            for arrival in arrivals { arrival.resume() }
            arrivals = []
            guard !isOpen else { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func arrival() async {
            guard fetches == 0 else { return }
            await withCheckedContinuation { arrivals.append($0) }
        }

        func open() {
            isOpen = true
            for continuation in waiting { continuation.resume() }
            waiting = []
        }
    }
}
