import Foundation
import Testing
@testable import PoliVerse

/// ``LoadWindow`` exists because a real device log showed the libretto, the
/// agenda and the WeBeep course list each fetched twice in one session purely
/// from switching tabs. These cover the two ways that fix could go wrong:
/// not suppressing anything, or suppressing something it must not.
@Suite("Load window")
struct LoadWindowTests {
    @Test("A first load always runs")
    func firstLoadRuns() {
        #expect(LoadWindow().shouldLoad())
    }

    @Test("A load just made is skipped")
    func recentLoadSkipped() {
        var window = LoadWindow(interval: 300)
        let now = Date(timeIntervalSince1970: 1_000_000)
        window.markLoaded(at: now)
        #expect(!window.shouldLoad(now: now.addingTimeInterval(60)))
    }

    @Test("A load past the window runs again")
    func staleLoadRuns() {
        var window = LoadWindow(interval: 300)
        let now = Date(timeIntervalSince1970: 1_000_000)
        window.markLoaded(at: now)
        #expect(window.shouldLoad(now: now.addingTimeInterval(301)))
    }

    @Test("Pull-to-refresh always runs")
    func forceAlwaysRuns() {
        var window = LoadWindow(interval: 300)
        let now = Date(timeIntervalSince1970: 1_000_000)
        window.markLoaded(at: now)
        #expect(window.shouldLoad(force: true, now: now))
    }

    /// The regression this guards: flipping "Usa dati di esempio" swaps every
    /// service's source, and that swap is only applied by the refetch. If the
    /// window suppressed it, Settings would appear to do nothing for five
    /// minutes.
    @Test("A changed source reloads however recent the last load was")
    func sourceChangeReloads() {
        var window = LoadWindow(interval: 300)
        let now = Date(timeIntervalSince1970: 1_000_000)
        window.markLoaded(source: "mock", at: now)
        #expect(window.shouldLoad(source: "10812345", now: now))
        #expect(!window.shouldLoad(source: "mock", now: now))
    }

    @Test("Invalidating forces the next load")
    func invalidateForcesReload() {
        var window = LoadWindow(interval: 300)
        let now = Date(timeIntervalSince1970: 1_000_000)
        window.markLoaded(source: "10812345", at: now)
        window.invalidate()
        #expect(window.shouldLoad(source: "10812345", now: now))
    }
}
