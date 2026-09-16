import Foundation
import Testing
@testable import PoliVerse

/// ``DataStatus`` is the only thing that decides *which* of several true facts
/// the app says, and the two rules that make it worth having are easy to break
/// silently: a quick refresh must say nothing at all, and sample data must win
/// over everything else. The rest is precedence, which is a switch statement
/// and so exactly the kind of thing a later edit reorders by accident.
@Suite("Stato dei dati")
@MainActor
struct DataStatusTests {
    /// Short enough to test against without spending a second of wall clock.
    private func make(sample: Bool = false) -> DataStatus {
        let session = Session()
        session.useMockData = sample
        return DataStatus(session: session, network: NetworkMonitor(),
                          quietInterval: .milliseconds(30),
                          confirmationInterval: .milliseconds(60))
    }

    /// Waits for a condition the class reaches on a timer of its own.
    ///
    /// The budget is generous because it is spent in wall clock while the
    /// progress it waits on needs the main actor: run in parallel with the
    /// `measure` blocks in ``HotPathPerformanceTests``, which hold the main
    /// thread for whole seconds at a time, a tighter deadline expires while
    /// the timer is merely waiting its turn. Nothing slow pays for it — the
    /// loop returns on the first poll that sees the condition.
    private func waitUntil(_ condition: () -> Bool, within: Duration = .seconds(30)) async throws {
        let deadline = ContinuousClock.now.advanced(by: within)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Con dati freschi non dice nulla")
    func quietWhenFine() {
        #expect(make().state == .idle)
        #expect(make().isQuiet)
        #expect(make().badge == nil)
    }

    /// The reason the line is not simply bound to `isLoading`: inside a tab
    /// view, most passes are served from ``LoadWindow`` and finish in a frame.
    @Test("Un aggiornamento istantaneo non compare")
    func staysQuietForAFastRefresh() async throws {
        let status = make()
        status.refreshBegan()
        status.refreshEnded()

        #expect(status.state == .idle)
        // Past the point where the line would have appeared, had it not been
        // cancelled by the pass finishing.
        try await Task.sleep(for: .milliseconds(80))
        #expect(status.state == .idle)
    }

    @Test("Un aggiornamento lento si annuncia, poi conferma")
    func announcesASlowRefresh() async throws {
        let status = make()
        status.refreshBegan()
        // Polled rather than slept through, for the same reason as the wait
        // below: the quiet interval is a floor, and a loaded machine can take
        // noticeably longer to come back to the timer.
        try await waitUntil { status.state == .refreshing }
        #expect(status.state == .refreshing)

        status.refreshEnded(at: .now)
        if case .updated = status.state {} else {
            Issue.record("dopo un aggiornamento visibile deve confermare, invece: \(status.state)")
        }
        // And the confirmation goes away on its own. Polled rather than slept
        // through: the interval is the floor, and a loaded machine can take
        // noticeably longer to come back to the timer.
        try await waitUntil { status.state == .idle }
        #expect(status.state == .idle)
    }

    @Test("Un servizio irraggiungibile viene nominato")
    func namesAFailedService() {
        let status = make()
        status.refreshBegan()
        status.refreshEnded(failures: ["Carriera"])

        #expect(status.state == .failed(["Carriera"]))
        #expect(status.badge == .attention)
        // The failure, not the clock: an error must not be overwritten by
        // "Aggiornato alle …" from the same pass.
        #expect(status.lastUpdated == nil)

        status.clearFailures()
        #expect(status.state == .idle)
        #expect(status.badge == nil)
    }

    @Test("I dati di esempio hanno la precedenza su tutto")
    func sampleWins() async throws {
        let status = make(sample: true)
        status.refreshBegan()
        try await Task.sleep(for: .milliseconds(60))
        #expect(status.state == .sample)

        status.refreshEnded(failures: ["Carriera"])
        #expect(status.state == .sample)
        #expect(status.badge == .sample)
    }
}
