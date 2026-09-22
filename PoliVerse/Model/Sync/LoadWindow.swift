import Foundation

/// A time-and-source gate that suppresses redundant refreshes of data that has
/// just been fetched.
///
/// SwiftUI's `.task` re-fires whenever its view appears, which inside a `TabView`
/// means every switch back to the tab. A window admits the first load, then
/// refuses further loads of the same source until ``interval`` has elapsed.
///
/// Two things always get through: a `force` call, which is how pull-to-refresh is
/// wired, and a change of source, which is how a sign-out or a flip of
/// ``Session/useMockData`` reaches the screen.
nonisolated struct LoadWindow: Sendable, Equatable {
    /// The interval a window uses when none is given: five minutes.
    static let defaultInterval: TimeInterval = 300

    /// How long a recorded load suppresses the next one.
    private let interval: TimeInterval
    /// When the last usable load completed, or `nil` before the first one and after
    /// ``invalidate()``.
    private var lastLoaded: Date?

    /// Creates a window that admits the first load immediately.
    ///
    /// - Parameter interval: How long a recorded load suppresses the next one.
    init(interval: TimeInterval = LoadWindow.defaultInterval) {
        self.interval = interval
    }

    /// What the recorded load describes — the matricola it belongs to, or a marker
    /// for sample data.
    ///
    /// A load whose source differs from this always goes through, however recent the
    /// last one was, because the held data belongs to a different account or to
    /// sample data.
    private var source: String?

    /// Whether a load should go to the network.
    ///
    /// - Parameters:
    ///   - force: Admits the load unconditionally.
    ///   - source: What the caller is about to load. A value different from the
    ///     recorded one admits the load.
    ///   - now: The clock, injectable for tests.
    /// - Returns: `true` when the load should proceed.
    func shouldLoad(force: Bool = false, source: String? = nil, now: Date = .now) -> Bool {
        if force { return true }
        guard let lastLoaded, source == self.source else { return true }
        return now.timeIntervalSince(lastLoaded) >= interval
    }

    /// Records a load that produced usable data.
    ///
    /// Only successful loads are recorded, so a failure is retried on the next
    /// appearance rather than being suppressed for the rest of the interval.
    ///
    /// - Parameters:
    ///   - source: What was loaded.
    ///   - date: When it completed.
    mutating func markLoaded(source: String? = nil, at date: Date = .now) {
        lastLoaded = date
        self.source = source
    }

    /// Forgets the recorded load, so the next call to ``shouldLoad(force:source:now:)``
    /// admits a load.
    ///
    /// Called on sign-out, and wherever held data stops being trustworthy.
    mutating func invalidate() {
        lastLoaded = nil
        source = nil
    }
}
