import Foundation
import Testing
@testable import PoliVerse

/// The things the app does while nobody is looking — a background refresh, a
/// widget reload, a Spotlight pass — left no trace but the system log. The
/// diagnostics page can only say "ultimo aggiornamento in background alle 6:12"
/// if that moment is written somewhere that outlives the process that did it.
@Suite("Registro di diagnostica")
struct DiagnosticsLogTests {
    /// A defaults suite of its own, so nothing leaks between tests or into the
    /// simulator's real preferences.
    private func withLog(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "diagnostics-log-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private let six = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("Senza niente registrato non inventa niente")
    func emptyLog() {
        withLog { defaults in
            let log = DiagnosticsLog(defaults: defaults)
            #expect(log.lastBackgroundRefresh == nil)
            #expect(log.lastWidgetReload == nil)
            #expect(log.lastSpotlightIndex == nil)
        }
    }

    @Test("Un aggiornamento in background concluso resta dopo il riavvio")
    func completedRunSurvives() {
        withLog { defaults in
            let first = DiagnosticsLog(defaults: defaults)
            first.backgroundRefreshStarted(at: six)
            first.backgroundRefreshFinished(at: six.addingTimeInterval(21), completed: true)

            let run = DiagnosticsLog(defaults: defaults).lastBackgroundRefresh
            #expect(run?.started == six)
            #expect(run?.finished == six.addingTimeInterval(21))
            #expect(run?.outcome == .completed)
        }
    }

    /// iOS gives a background task about thirty seconds and then ends it.
    @Test("Un aggiornamento interrotto dal sistema lo dice")
    func expiredRun() {
        withLog { defaults in
            let log = DiagnosticsLog(defaults: defaults)
            log.backgroundRefreshStarted(at: six)
            log.backgroundRefreshFinished(at: six.addingTimeInterval(30), completed: false)
            #expect(log.lastBackgroundRefresh?.outcome == .expired)
        }
    }

    /// A process killed mid-run never reaches its "finished" line: the run must
    /// read as unfinished rather than borrow the end of the one before it.
    @Test("Un avvio senza fine non eredita la fine del giro precedente")
    func startWithoutFinish() {
        withLog { defaults in
            let log = DiagnosticsLog(defaults: defaults)
            log.backgroundRefreshStarted(at: six)
            log.backgroundRefreshFinished(at: six.addingTimeInterval(20), completed: true)
            log.backgroundRefreshStarted(at: six.addingTimeInterval(3600))

            let run = DiagnosticsLog(defaults: defaults).lastBackgroundRefresh
            #expect(run?.started == six.addingTimeInterval(3600))
            #expect(run?.finished == nil)
            #expect(run?.outcome == .unfinished)
        }
    }

    @Test("Ricarica dei widget e indicizzazione Spotlight restano dopo il riavvio")
    func widgetsAndSpotlightSurvive() {
        withLog { defaults in
            let first = DiagnosticsLog(defaults: defaults)
            first.widgetsReloaded(at: six)
            first.spotlightIndexed(count: 42, at: six.addingTimeInterval(5))

            let second = DiagnosticsLog(defaults: defaults)
            #expect(second.lastWidgetReload == six)
            #expect(second.lastSpotlightIndex?.count == 42)
            #expect(second.lastSpotlightIndex?.date == six.addingTimeInterval(5))
        }
    }
}
