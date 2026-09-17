import Foundation

/// When the app last did the things it does while nobody is looking.
///
/// A background refresh, a widget reload and a Spotlight pass used to leave
/// no trace but the unified log, which a student cannot read and a bug report
/// never includes. The diagnostics page needs "ultimo aggiornamento in
/// background alle 6:12, concluso" — so the moment is written to defaults,
/// where it outlives the process that did the work.
///
/// Timestamps only: nothing here is personal, and nothing is kept but the
/// latest of each.
nonisolated struct DiagnosticsLog: @unchecked Sendable {
    /// One background refresh, as far as it got.
    struct BackgroundRun: Equatable, Sendable {
        enum Outcome: Equatable, Sendable {
            /// Everything ran before the deadline.
            case completed
            /// iOS ended the task first.
            case expired
            /// Started and never reported back: the process was killed, or it
            /// is still running.
            case unfinished
        }

        let started: Date
        let finished: Date?
        let outcome: Outcome
    }

    static let shared = DiagnosticsLog(defaults: .standard)

    // `UserDefaults` is thread-safe; the struct holds nothing else.
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private enum Key {
        static let backgroundStarted = "diagnostics.background.started"
        static let backgroundFinished = "diagnostics.background.finished"
        static let backgroundCompleted = "diagnostics.background.completed"
        static let widgetReload = "diagnostics.widgets.reloaded"
        static let spotlightDate = "diagnostics.spotlight.date"
        static let spotlightCount = "diagnostics.spotlight.count"
    }

    // MARK: - Background refresh

    func backgroundRefreshStarted(at date: Date = .now) {
        defaults.set(date, forKey: Key.backgroundStarted)
        // A new run owns no end yet. Left in place, the previous run's finish
        // would make a run killed halfway read as completed.
        defaults.removeObject(forKey: Key.backgroundFinished)
        defaults.removeObject(forKey: Key.backgroundCompleted)
    }

    /// - Parameter completed: false when iOS's expiration handler ended the
    ///   task before the work was done.
    func backgroundRefreshFinished(at date: Date = .now, completed: Bool) {
        defaults.set(date, forKey: Key.backgroundFinished)
        defaults.set(completed, forKey: Key.backgroundCompleted)
    }

    var lastBackgroundRefresh: BackgroundRun? {
        guard let started = defaults.object(forKey: Key.backgroundStarted) as? Date else { return nil }
        guard let finished = defaults.object(forKey: Key.backgroundFinished) as? Date else {
            return BackgroundRun(started: started, finished: nil, outcome: .unfinished)
        }
        return BackgroundRun(started: started, finished: finished,
                             outcome: defaults.bool(forKey: Key.backgroundCompleted) ? .completed : .expired)
    }

    // MARK: - Widgets and Spotlight

    func widgetsReloaded(at date: Date = .now) {
        defaults.set(date, forKey: Key.widgetReload)
    }

    var lastWidgetReload: Date? {
        defaults.object(forKey: Key.widgetReload) as? Date
    }

    func spotlightIndexed(count: Int, at date: Date = .now) {
        defaults.set(date, forKey: Key.spotlightDate)
        defaults.set(count, forKey: Key.spotlightCount)
    }

    var lastSpotlightIndex: (count: Int, date: Date)? {
        guard let date = defaults.object(forKey: Key.spotlightDate) as? Date else { return nil }
        return (defaults.integer(forKey: Key.spotlightCount), date)
    }
}
