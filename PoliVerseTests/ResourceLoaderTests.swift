import Foundation
import Testing
@testable import PoliVerse

/// The loader every service will sit on.
///
/// Four services had grown their own version of "have I already fetched
/// this?", each subtly different, and none of them coalesced concurrent
/// callers or prefetched anything. These pin the behaviour that made it worth
/// having one.
@Suite("Resource loader")
struct ResourceLoaderTests {
    /// Counts how many times the work actually ran, which is the whole point.
    private actor Counter {
        private(set) var runs: [String: Int] = [:]
        func record(_ key: String) { runs[key, default: 0] += 1 }
        func count(_ key: String) -> Int { runs[key] ?? 0 }
        var total: Int { runs.values.reduce(0, +) }
    }

    @Test("A value is fetched once and then served from memory")
    func cacheHit() async {
        let counter = Counter()
        let loader = ResourceLoader<String, String> { key in
            await counter.record(key)
            return key.uppercased()
        }

        #expect(await loader.value(for: "a") == "A")
        #expect(await loader.value(for: "a") == "A")
        #expect(await counter.count("a") == 1)
    }

    /// The case an ad-hoc `isLoading` flag gets wrong: two screens asking at
    /// once. A flag makes the second caller give up and show nothing; this
    /// makes it wait for the first one's answer.
    @Test("Concurrent callers share one fetch and all get the value")
    func coalesces() async {
        let counter = Counter()
        let loader = ResourceLoader<String, String> { key in
            try? await Task.sleep(for: .milliseconds(40))
            await counter.record(key)
            return key.uppercased()
        }

        let results = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<8 {
                group.addTask { await loader.value(for: "a") }
            }
            var all: [String?] = []
            for await result in group { all.append(result) }
            return all
        }

        #expect(results.allSatisfy { $0 == "A" })
        #expect(await counter.count("a") == 1)
    }

    /// The subtlety that makes this worth writing rather than reaching for a
    /// plain `Task` per call site: if one screen goes away mid-fetch, the
    /// other screens waiting on the same resource must still get their value.
    @Test("A cancelled caller does not cancel the shared work")
    func cancellationIsPerCaller() async {
        let counter = Counter()
        let loader = ResourceLoader<String, String> { key in
            try? await Task.sleep(for: .milliseconds(60))
            await counter.record(key)
            return key.uppercased()
        }

        let doomed = Task { await loader.value(for: "a") }
        let survivor = Task { await loader.value(for: "a") }
        try? await Task.sleep(for: .milliseconds(10))
        doomed.cancel()

        #expect(await survivor.value == "A")
        #expect(await counter.count("a") == 1)
    }

    @Test("Different keys are fetched independently")
    func independentKeys() async {
        let counter = Counter()
        let loader = ResourceLoader<String, String> { key in
            await counter.record(key)
            return key.uppercased()
        }
        _ = await loader.value(for: "a")
        _ = await loader.value(for: "b")
        #expect(await counter.total == 2)
    }

    /// A failure must not be cached, or one flaky moment poisons the resource
    /// for the lifetime of the app.
    @Test("A failure is not cached and the next attempt runs again")
    func failuresAreNotCached() async {
        let counter = Counter()
        let loader = ResourceLoader<String, String> { key in
            await counter.record(key)
            return await counter.count(key) < 2 ? nil : "ok"
        }

        #expect(await loader.value(for: "a") == nil)
        #expect(await loader.value(for: "a") == "ok")
        #expect(await counter.count("a") == 2)
    }

    @Test("An entry past its lifetime is fetched again")
    func expiry() async {
        let counter = Counter()
        let loader = ResourceLoader<String, String>(lifetime: .milliseconds(30)) { key in
            await counter.record(key)
            return key.uppercased()
        }
        _ = await loader.value(for: "a")
        await loader.settle()
        try? await Task.sleep(for: .milliseconds(50))
        _ = await loader.value(for: "a")
        #expect(await counter.count("a") == 2)
    }

    /// Prefetching is the reason this exists: warm the next thing while the
    /// user reads this one, so opening it costs nothing.
    @Test("A prefetched value is already there when asked for")
    func prefetch() async {
        let counter = Counter()
        let loader = ResourceLoader<String, String> { key in
            try? await Task.sleep(for: .milliseconds(20))
            await counter.record(key)
            return key.uppercased()
        }

        await loader.prefetch("a")
        // Awaited rather than slept on: a prefetch runs at background
        // priority, which the system may starve for a long time under load,
        // and a sleeping test would be flaky rather than wrong.
        await loader.settle()
        #expect(await loader.isCached("a"))
        #expect(await loader.value(for: "a") == "A")
        #expect(await counter.count("a") == 1)
    }

    @Test("Prefetching something already in flight does not start a second fetch")
    func prefetchJoinsInFlight() async {
        let counter = Counter()
        let loader = ResourceLoader<String, String> { key in
            try? await Task.sleep(for: .milliseconds(30))
            await counter.record(key)
            return key.uppercased()
        }
        await loader.prefetch("a")
        await loader.prefetch("a")
        await loader.settle()
        _ = await loader.value(for: "a")
        #expect(await counter.count("a") == 1)
    }

    /// Bounded, or a long session in the rooms list holds every floor plan it
    /// ever showed.
    @Test("The cache stays within its capacity, keeping what was used last")
    func eviction() async {
        let loader = ResourceLoader<String, String>(capacity: 3) { $0.uppercased() }
        for key in ["a", "b", "c"] { _ = await loader.value(for: key) }
        // Touch "a" so it is the most recently used, then overflow.
        _ = await loader.value(for: "a")
        _ = await loader.value(for: "d")

        #expect(await loader.count <= 3)
        #expect(await loader.isCached("a"))
        #expect(await loader.isCached("d"))
        #expect(!(await loader.isCached("b")))
    }

    /// `settle()` has to wait for the cache to be *written*, not merely for
    /// the fetch to return — the write happens in a second task, and an
    /// earlier version spun forever on an entry nothing would clear.
    @Test("Settling waits for prefetches to be filed, not just fetched")
    func settleWaitsForTheWrite() async {
        let loader = ResourceLoader<String, String> { key in
            try? await Task.sleep(for: .milliseconds(20))
            return key.uppercased()
        }
        await loader.prefetch(["a", "b", "c"])
        await loader.settle()
        #expect(await loader.count == 3)
    }

    @Test("Settling with nothing in flight returns immediately")
    func settleWhenIdle() async {
        let loader = ResourceLoader<String, String> { $0.uppercased() }
        await loader.settle()
        #expect(await loader.count == 0)
    }

    @Test("Invalidating one key leaves the others alone")
    func invalidateOne() async {
        let loader = ResourceLoader<String, String> { $0.uppercased() }
        _ = await loader.value(for: "a")
        _ = await loader.value(for: "b")
        await loader.invalidate("a")
        #expect(!(await loader.isCached("a")))
        #expect(await loader.isCached("b"))
    }

    @Test("Clearing empties everything, for sign-out")
    func clear() async {
        let loader = ResourceLoader<String, String> { $0.uppercased() }
        _ = await loader.value(for: "a")
        await loader.clear()
        #expect(await loader.count == 0)
    }
}
