import Foundation
import Testing
@testable import PoliVerse

/// ``FreshnessCoordinator`` exists because the same list of five loads was
/// written out in three places, and two of the moments that should have
/// triggered it — coming back to the app, and getting signal back — triggered
/// nothing at all. These cover the parts that could go wrong once something
/// other than a view starts asking for data: running the wrong set, running it
/// twice at once, and losing the `force` flag on the way through.
@Suite("Freshness coordinator")
@MainActor
struct FreshnessCoordinatorTests {
    @Test("Revalidating runs every registered load")
    func runsEveryLoad() async {
        let coordinator = FreshnessCoordinator()
        let calls = Recorder()
        coordinator.register("agenda") { _ in calls.record("agenda") }
        coordinator.register("career") { _ in calls.record("career") }

        await coordinator.revalidate()

        #expect(calls.names == ["agenda", "career"])
    }

    @Test("Loads run in the order they were registered")
    func runsInOrder() async {
        let coordinator = FreshnessCoordinator()
        let calls = Recorder()
        for name in ["courses", "agenda", "career", "notices", "news"] {
            coordinator.register(name) { _ in calls.record(name) }
        }

        await coordinator.revalidate()

        #expect(calls.names == ["courses", "agenda", "career", "notices", "news"])
    }

    @Test("The force flag reaches each load")
    func forwardsForce() async {
        let coordinator = FreshnessCoordinator()
        let forced = Recorder()
        coordinator.register("agenda") { force in forced.record(force ? "forced" : "gentle") }

        await coordinator.revalidate(force: true)
        await coordinator.revalidate(force: false)

        #expect(forced.names == ["forced", "gentle"])
    }

    /// Foregrounding and reconnecting can land within a frame of each other —
    /// unlock the phone in a lift as signal returns — and that must not put
    /// two of every request on the wire.
    @Test("A revalidation already in flight is not started twice")
    func coalescesConcurrentRuns() async {
        let coordinator = FreshnessCoordinator()
        let calls = Recorder()
        coordinator.register("agenda") { _ in
            calls.record("agenda")
            await Task.yield()
        }

        async let first: Void = coordinator.revalidate()
        async let second: Void = coordinator.revalidate()
        _ = await (first, second)

        #expect(calls.names == ["agenda"])
    }

    /// The coalescing must not be permanent: the next foregrounding is a new
    /// moment and deserves its own look at the server.
    @Test("A later revalidation runs again")
    func runsAgainAfterFinishing() async {
        let coordinator = FreshnessCoordinator()
        let calls = Recorder()
        coordinator.register("agenda") { _ in calls.record("agenda") }

        await coordinator.revalidate()
        await coordinator.revalidate()

        #expect(calls.names == ["agenda", "agenda"])
    }

    /// A forced run is a stronger promise than a gentle one, so it must not be
    /// satisfied by whatever gentle run happens to be in flight.
    @Test("A forced revalidation is not swallowed by a gentle one in flight")
    func forcedRunFollowsGentleRun() async {
        let coordinator = FreshnessCoordinator()
        let calls = Recorder()
        coordinator.register("agenda") { force in
            calls.record(force ? "forced" : "gentle")
            await Task.yield()
        }

        async let gentle: Void = coordinator.revalidate()
        async let forced: Void = coordinator.revalidate(force: true)
        _ = await (gentle, forced)

        // Chained, not raced: two passes writing the same service's cache from
        // two directions is the bug the ordering avoids.
        #expect(calls.names == ["gentle", "forced"])
    }

    /// The case that made the first version of the coalescing wrong: a forced
    /// run arriving while an earlier forced run is already halfway through its
    /// list was satisfied by that one. Pull to refresh twice and the second
    /// pull fetched nothing.
    @Test("Each forced revalidation gets a pass of its own")
    func everyForcedRunFetches() async {
        let coordinator = FreshnessCoordinator()
        let calls = Recorder()
        coordinator.register("agenda") { _ in
            calls.record("agenda")
            await Task.yield()
        }

        async let first: Void = coordinator.revalidate(force: true)
        async let second: Void = coordinator.revalidate(force: true)
        async let third: Void = coordinator.revalidate(force: true)
        _ = await (first, second, third)

        #expect(calls.names == ["agenda", "agenda", "agenda"])
    }

    /// The other half of that: a gentle run must still be free, however many
    /// arrive while one is running.
    @Test("Gentle revalidations still join the run in flight")
    func gentleRunsJoin() async {
        let coordinator = FreshnessCoordinator()
        let calls = Recorder()
        coordinator.register("agenda") { _ in
            calls.record("agenda")
            await Task.yield()
        }

        async let first: Void = coordinator.revalidate()
        async let second: Void = coordinator.revalidate()
        async let third: Void = coordinator.revalidate()
        _ = await (first, second, third)

        #expect(calls.names == ["agenda"])
    }

    @MainActor
    private final class Recorder {
        private(set) var names: [String] = []
        func record(_ name: String) { names.append(name) }
    }
}
