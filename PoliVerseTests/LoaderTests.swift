import Foundation
import Testing
@testable import PoliVerse

/// The loader every remote resource goes through.
///
/// Five ways of answering "have I already fetched this?" had grown in the app,
/// each subtly different; the bugs of September 2026 lived in the gaps between
/// them. These pin the one answer: joining, keeping, warming, cancelling only
/// when nobody is left, batching, and the offline copy.
///
/// Waits are gates the test opens, not sleeps, wherever the order matters.
@Suite("Loader", .tags(.timing))
struct LoaderTests {
    private static let env = Env(http: FixtureHTTP(), matricola: "111", isSample: false)

    // MARK: - Resources to load

    /// Counts how many times the work actually ran, which is the whole point.
    private actor Counter {
        private(set) var runs: [String: Int] = [:]
        private(set) var batches = 0
        func record(_ key: String) { runs[key, default: 0] += 1 }
        func batch() { batches += 1 }
        func count(_ key: String) -> Int { runs[key] ?? 0 }
    }

    /// Upper-cases its key, after whatever `work` does first.
    private nonisolated struct Echo: Resource {
        static let id = "echo"
        static let persistence = Persistence.memory
        let counter: Counter
        var before: @Sendable (String) async throws -> Void = { _ in }

        @concurrent
        func fetch(_ key: String, env: Env, previous: String?) async throws -> String {
            try await before(key)
            await counter.record(key)
            return key.uppercased()
        }
    }

    /// Echo that expires almost at once.
    private nonisolated struct ShortLived: Resource {
        static let id = "short"
        static let ttl: TimeInterval = 0.05
        static let persistence = Persistence.memory
        let counter: Counter

        @concurrent
        func fetch(_ key: String, env: Env, previous: String?) async throws -> String {
            await counter.record(key)
            return key.uppercased()
        }
    }

    /// Answers several keys in one call, like the agenda's weeks.
    private nonisolated struct Batched: Resource {
        static let id = "batched"
        static let persistence = Persistence.memory
        let counter: Counter

        @concurrent
        func fetch(_ key: String, env: Env, previous: String?) async throws -> String {
            try await fetch([key], env: env, previous: [:])[key] ?? ""
        }

        @concurrent
        func fetch(_ keys: [String], env: Env, previous: [String: String]) async throws -> [String: String] {
            await counter.batch()
            return Dictionary(uniqueKeysWithValues: keys.map { ($0, $0.uppercased()) })
        }
    }

    /// A `Codable` value written to disk, with a sample.
    private nonisolated struct Stored: Resource {
        static let id = "stored"
        let counter: Counter

        @concurrent
        func fetch(_ key: Whole, env: Env, previous: String?) async throws -> String {
            await counter.record("stored")
            return "fetched"
        }

        func sample(_ key: Whole) -> String? { "sample" }
    }

    private struct Boom: Error {}

    /// Holds a fetch until the test opens it, and says when one arrived.
    private actor Gate {
        private var isOpen = false
        private var arrived = 0
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var arrivals: [CheckedContinuation<Void, Never>] = []

        func pass() async {
            arrived += 1
            for arrival in arrivals { arrival.resume() }
            arrivals = []
            guard !isOpen else { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func arrival() async {
            guard arrived == 0 else { return }
            await withCheckedContinuation { arrivals.append($0) }
        }

        func open() {
            isOpen = true
            for continuation in waiting { continuation.resume() }
            waiting = []
        }
    }

    private func offline() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("loader-\(UUID().uuidString)", isDirectory: true))
    }

    // MARK: - Joining and keeping

    @Test("A value is fetched once and then served from memory")
    func cacheHit() async throws {
        let counter = Counter()
        let loader = Loader(Echo(counter: counter))

        #expect(try await loader.value("a", env: Self.env).value == "A")
        #expect(try await loader.value("a", env: Self.env).value == "A")
        #expect(await counter.count("a") == 1)
    }

    /// The case an `isLoading` flag gets wrong: two screens asking at once. A
    /// flag makes the second caller give up and show nothing; this makes it
    /// wait for the first one's answer.
    @Test("Concurrent callers share one fetch and all get the value")
    func joins() async {
        let counter = Counter()
        let gate = Gate()
        let loader = Loader(Echo(counter: counter, before: { _ in await gate.pass() }))

        let callers = (0..<8).map { _ in Task { try? await loader.value("a", env: Self.env).value } }
        await gate.arrival()
        await gate.open()
        var results: [String?] = []
        for caller in callers { results.append(await caller.value) }

        #expect(results.allSatisfy { $0 == "A" })
        #expect(await counter.count("a") == 1)
    }

    /// If one screen goes away mid-fetch, the others waiting on the same
    /// resource must still get their value.
    @Test("A cancelled caller does not cancel the work others wait for")
    func cancellationIsPerCaller() async {
        let counter = Counter()
        let gate = Gate()
        let loader = Loader(Echo(counter: counter, before: { _ in await gate.pass() }))

        let doomed = Task { try? await loader.value("a", env: Self.env).value }
        await gate.arrival()
        let survivor = Task { try? await loader.value("a", env: Self.env).value }
        await Task.yield()
        doomed.cancel()
        await gate.open()

        #expect(await survivor.value == "A")
        #expect(await counter.count("a") == 1)
    }

    /// When the only screen waiting goes away, the request stops with it:
    /// nobody is left to show the answer to.
    @Test("The last caller leaving cancels the fetch")
    func lastCallerCancels() async {
        let counter = Counter()
        let gate = Gate()
        let (cancelled, signal) = AsyncStream.makeStream(of: Void.self)
        let loader = Loader(Echo(counter: counter, before: { _ in
            try await withTaskCancellationHandler {
                await gate.pass()
                try Task.checkCancellation()
            } onCancel: {
                signal.yield()
            }
        }))

        let only = Task { try? await loader.value("a", env: Self.env).value }
        await gate.arrival()
        only.cancel()
        for await _ in cancelled { break }
        await gate.open()
        await loader.settle()

        #expect(await only.value == nil)
        #expect(await counter.count("a") == 0)
        #expect(await loader.count == 0)
    }

    @Test("Different keys are fetched independently")
    func independentKeys() async throws {
        let counter = Counter()
        let loader = Loader(Echo(counter: counter))
        _ = try await loader.value("a", env: Self.env)
        _ = try await loader.value("b", env: Self.env)
        #expect(await counter.count("a") == 1)
        #expect(await counter.count("b") == 1)
    }

    @Test("A failure is not cached and the next attempt runs again")
    func failureIsNotCached() async throws {
        let counter = Counter()
        let attempts = Counter()
        let loader = Loader(Echo(counter: counter, before: { key in
            await attempts.record(key)
            if await attempts.count(key) == 1 { throw Boom() }
        }))

        await #expect(throws: Boom.self) { try await loader.value("a", env: Self.env) }
        #expect(try await loader.value("a", env: Self.env).value == "A")
    }

    @Test("An entry past its lifetime is fetched again")
    func expiry() async throws {
        let counter = Counter()
        let loader = Loader(ShortLived(counter: counter))
        _ = try await loader.value("a", env: Self.env)
        try await Task.sleep(for: .milliseconds(120))
        _ = try await loader.value("a", env: Self.env)
        #expect(await counter.count("a") == 2)
    }

    @Test("A forced load fetches even a fresh key")
    func force() async throws {
        let counter = Counter()
        let loader = Loader(Echo(counter: counter))
        _ = try await loader.value("a", env: Self.env)
        _ = try await loader.value("a", env: Self.env, force: true)
        #expect(await counter.count("a") == 2)
    }

    /// Switching account, or turning sample data on, changes what a held
    /// value describes.
    @Test("A value held for one account is never served to another")
    func perAccount() async throws {
        let counter = Counter()
        let loader = Loader(Echo(counter: counter))
        let other = Env(http: FixtureHTTP(), matricola: "222", isSample: false)
        _ = try await loader.value("a", env: Self.env)
        #expect(await loader.cached("a", env: other) == nil)
        _ = try await loader.value("a", env: other)
        #expect(await counter.count("a") == 2)
    }

    // MARK: - Batching

    /// The agenda's endpoint answers a span in one request; six weeks must not
    /// cost six.
    @Test("Keys not held are fetched in one call")
    func batches() async throws {
        let counter = Counter()
        let loader = Loader(Batched(counter: counter))
        let values = try await loader.values(["a", "b", "c"], env: Self.env)
        #expect(values.mapValues(\.value) == ["a": "A", "b": "B", "c": "C"])
        #expect(await counter.batches == 1)

        // Only the key not held goes out.
        _ = try await loader.values(["a", "b", "d"], env: Self.env)
        #expect(await counter.batches == 2)
        #expect(await loader.count == 4)
    }

    // MARK: - Warming

    @Test("A warmed value is already there when asked for")
    func warm() async throws {
        let counter = Counter()
        let loader = Loader(Echo(counter: counter))
        await loader.warm(["a", "b"], env: Self.env)
        await loader.settle()
        #expect(await loader.isHeld("a", env: Self.env))
        _ = try await loader.value("a", env: Self.env)
        #expect(await counter.count("a") == 1)
    }

    @Test("Warming something already in flight does not start a second fetch")
    func warmJoinsInFlight() async throws {
        let counter = Counter()
        let gate = Gate()
        let loader = Loader(Echo(counter: counter, before: { _ in await gate.pass() }))
        await loader.warm(["a"], env: Self.env)
        await loader.warm(["a"], env: Self.env)
        let asked = Task { try await loader.value("a", env: Self.env).value }
        await gate.arrival()
        await gate.open()
        #expect(try await asked.value == "A")
        #expect(await counter.count("a") == 1)
    }

    @Test("Settling waits for warm-ups to be filed, not just fetched")
    func settleWaitsForTheWrite() async {
        let loader = Loader(Echo(counter: Counter()))
        await loader.warm(["a", "b", "c"], env: Self.env)
        await loader.settle()
        #expect(await loader.count == 3)
    }

    @Test("Settling with nothing in flight returns immediately")
    func settleWhenIdle() async {
        let loader = Loader(Echo(counter: Counter()))
        await loader.settle()
        #expect(await loader.count == 0)
    }

    // MARK: - Bounds and sign-out

    /// Bounded, or a long session in the rooms list holds every room it ever
    /// showed.
    @Test("The cache stays within its capacity, keeping what was used last")
    func eviction() async throws {
        let loader = Loader(Echo(counter: Counter()), capacity: 3)
        for key in ["a", "b", "c"] { _ = try await loader.value(key, env: Self.env) }
        // Touch "a" so it is the most recently used, then overflow.
        _ = try await loader.value("a", env: Self.env)
        _ = try await loader.value("d", env: Self.env)

        #expect(await loader.count <= 3)
        #expect(await loader.isHeld("a", env: Self.env))
        #expect(await loader.isHeld("d", env: Self.env))
        #expect(!(await loader.isHeld("b", env: Self.env)))
    }

    @Test("Invalidating one key leaves the others alone")
    func invalidateOne() async throws {
        let loader = Loader(Echo(counter: Counter()))
        _ = try await loader.value("a", env: Self.env)
        _ = try await loader.value("b", env: Self.env)
        await loader.invalidate("a")
        #expect(!(await loader.isHeld("a", env: Self.env)))
        #expect(await loader.isHeld("b", env: Self.env))
    }

    @Test("Clearing empties everything, for sign-out")
    func clear() async throws {
        let loader = Loader(Echo(counter: Counter()))
        _ = try await loader.value("a", env: Self.env)
        await loader.clear()
        #expect(await loader.count == 0)
    }

    // MARK: - The offline copy

    @Test("A fetched value is written per account, sample data and nobody's never")
    func writesOfflineCopy() async throws {
        let offline = offline()
        let loader = Loader(Stored(counter: Counter()), offline: offline)
        _ = try await loader.value(Whole(), env: Self.env)
        _ = try await loader.value(Whole(), env: Env(http: FixtureHTTP(), matricola: "222", isSample: true))
        _ = try await loader.value(Whole(), env: Env(http: FixtureHTTP(), matricola: nil, isSample: false))
        offline.flush()

        #expect(offline.load(String.self, as: Stored.id, account: "111")?.value == "fetched")
        #expect(offline.load(String.self, as: Stored.id, account: "222") == nil)
    }

    @Test("The offline copy is restored once per account, and never counts as fresh")
    func restoresOnce() async {
        let offline = offline()
        offline.save("cached", as: Stored.id, account: "111")
        let loader = Loader(Stored(counter: Counter()), offline: offline)

        let restored = await loader.restore(Whole(), env: Self.env)
        #expect(restored?.value == "cached")
        #expect(restored?.isFresh == false)
        #expect(await loader.restore(Whole(), env: Self.env) == nil)
        #expect(await loader.isDue(Whole(), env: Self.env))
    }

    /// A copy read from disk after the network already answered would put
    /// older data over newer.
    @Test("A restore that a fetch overtook is dropped")
    func restoreOvertaken() async throws {
        let offline = offline()
        offline.save("cached", as: Stored.id, account: "111")
        let loader = Loader(Stored(counter: Counter()), offline: offline)

        _ = try await loader.value(Whole(), env: Self.env)
        #expect(await loader.restore(Whole(), env: Self.env) == nil)
        #expect(await loader.cached(Whole(), env: Self.env)?.value == "fetched")
    }

    @Test("Sample data is served without fetching and never restored")
    func sample() async throws {
        let counter = Counter()
        let loader = Loader(Stored(counter: counter), offline: offline())
        let sample = Env(http: FixtureHTTP(), matricola: "111", isSample: true)
        #expect(try await loader.value(Whole(), env: sample).value == "sample")
        #expect(await counter.count("stored") == 0)
        #expect(await loader.restore(Whole(), env: sample) == nil)
    }
}
