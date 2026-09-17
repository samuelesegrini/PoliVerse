import Foundation

/// Suppresses redundant refreshes of data that has just been fetched.
///
/// SwiftUI's `.task` re-fires every time its view appears, and inside a
/// `TabView` that means every switch back to the tab. On a real account this
/// showed up plainly in the log: the libretto, the agenda and the WeBeep course
/// list were each fetched twice in one session, purely from moving between
/// tabs. Nothing had changed in between — it was three round trips and a
/// visible spinner for data already on screen.
///
/// Pull-to-refresh passes `force`, so the user can always demand fresh data;
/// this only stops the app refetching on its own behalf.
nonisolated struct LoadWindow: Sendable, Equatable {
    /// How long a load stays good for. Comfortably longer than a tab switch,
    /// far shorter than anything upstream is likely to change in.
    static let defaultInterval: TimeInterval = 300

    private let interval: TimeInterval
    private var lastLoaded: Date?

    init(interval: TimeInterval = LoadWindow.defaultInterval) {
        self.interval = interval
    }

    /// What the held data describes — the matricola it belongs to, or the fact
    /// that it is sample data.
    ///
    /// Without this the window would hold the wrong data past the moment it
    /// became wrong: flipping "Usa dati di esempio" in Settings swaps every
    /// service's source, and that swap is only applied by the refetch the
    /// window would otherwise suppress. The same goes for signing out and back
    /// in. A changed source always reloads, however recent the last one was.
    private var source: String?

    /// Whether a load should actually go to the network.
    func shouldLoad(force: Bool = false, source: String? = nil, now: Date = .now) -> Bool {
        if force { return true }
        guard let lastLoaded, source == self.source else { return true }
        return now.timeIntervalSince(lastLoaded) >= interval
    }

    /// Records a load that produced usable data. A failed load deliberately
    /// does not mark, so the next appearance retries rather than serving an
    /// error for five minutes.
    mutating func markLoaded(source: String? = nil, at date: Date = .now) {
        lastLoaded = date
        self.source = source
    }

    /// Forgets the last load, so the next call refetches. Used on logout, and
    /// whenever held data stops being trustworthy.
    mutating func invalidate() {
        lastLoaded = nil
        source = nil
    }
}
