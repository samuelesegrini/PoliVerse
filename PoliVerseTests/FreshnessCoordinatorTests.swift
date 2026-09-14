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

        await overlap(coordinator, first: false, then: [false]) { _ in calls.record("agenda") }

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

        await overlap(coordinator, first: false, then: [true]) { force in
            calls.record(force ? "forced" : "gentle")
        }

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

        await overlap(coordinator, first: true, then: [true, true]) { _ in calls.record("agenda") }

        #expect(calls.names == ["agenda", "agenda", "agenda"])
    }

    /// The other half of that: a gentle run must still be free, however many
    /// arrive while one is running.
    @Test("Gentle revalidations still join the run in flight")
    func gentleRunsJoin() async {
        let coordinator = FreshnessCoordinator()
        let calls = Recorder()

        await overlap(coordinator, first: false, then: [false, false]) { _ in calls.record("agenda") }

        #expect(calls.names == ["agenda"])
    }

    /// Registers a load that records each pass, starts a revalidation, and
    /// starts the `then` ones only once its pass is really running, holding
    /// that pass open until every one of them has arrived.
    ///
    /// Starting them all at once with `async let` leaves their order to the
    /// scheduler, and a later call that happens to start after the first pass
    /// has finished tests nothing. Everything here shares the main actor, so
    /// the held pass cannot resume between a later task announcing itself and
    /// its `revalidate` reaching its first suspension — by which point that
    /// call has already seen the pass in flight.
    private func overlap(
        _ coordinator: FreshnessCoordinator,
        first: Bool,
        then later: [Bool],
        record: @escaping @MainActor (_ force: Bool) -> Void
    ) async {
        let (started, startedSignal) = AsyncStream.makeStream(of: Void.self)
        let (arrived, arrivalSignal) = AsyncStream.makeStream(of: Void.self)
        let passes = Recorder()
        coordinator.register("agenda") { force in
            record(force)
            passes.record("pass")
            guard passes.names.count == 1 else { return }
            startedSignal.yield()
            var waiting = later.count
            for await _ in arrived {
                waiting -= 1
                if waiting == 0 { break }
            }
        }

        let firstRun = Task { await coordinator.revalidate(force: first) }
        for await _ in started { break }
        let laterRuns = later.map { force in
            Task {
                arrivalSignal.yield()
                await coordinator.revalidate(force: force)
            }
        }
        await firstRun.value
        for run in laterRuns { await run.value }
    }

    @MainActor
    private final class Recorder {
        private(set) var names: [String] = []
        func record(_ name: String) { names.append(name) }
    }
}
