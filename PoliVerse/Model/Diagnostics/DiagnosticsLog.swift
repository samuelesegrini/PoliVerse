import Foundation

/// When the app last did the things it does while nobody is looking: a background
/// refresh, a widget reload, a Spotlight pass.
///
/// Written to `UserDefaults`, so the moment outlives the process that did the work and
/// the diagnostics page can report it. The unified log is the only other witness, and a
/// student cannot read it.
///
/// Timestamps and counts only: nothing here is personal, and only the latest of each is
/// kept.
///
/// `@unchecked Sendable` because `UserDefaults` is thread-safe and the struct holds
/// nothing else.
nonisolated struct DiagnosticsLog: @unchecked Sendable {
    /// One background refresh, as far as it got.
    struct BackgroundRun: Equatable, Sendable {
        /// How a background refresh ended.
        enum Outcome: Equatable, Sendable {
            /// Everything ran before the deadline.
            case completed
            /// iOS ended the task first.
            case expired
            /// Started and never reported back: the process was killed, or the run is still going.
            case unfinished
        }

        /// When the run began.
        let started: Date
        /// When it ended, or `nil` when it never reported back.
        let finished: Date?
        /// How it ended.
        let outcome: Outcome
    }

    /// The log the app writes to.
    static let shared = DiagnosticsLog(defaults: .standard)

    // `UserDefaults` is thread-safe; the struct holds nothing else.
    /// Where the timestamps are stored.
    private let defaults: UserDefaults

    /// Creates a log.
    ///
    /// - Parameter defaults: Where the timestamps are stored.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The defaults keys each fact is stored under.
    private enum Key {
        /// When the last background refresh began.
        static let backgroundStarted = "diagnostics.background.started"
        /// When it ended, absent while it has not.
        static let backgroundFinished = "diagnostics.background.finished"
        /// Whether it finished its work rather than being ended by iOS.
        static let backgroundCompleted = "diagnostics.background.completed"
        /// When the widgets were last asked to reload.
        static let widgetReload = "diagnostics.widgets.reloaded"
        /// When the last Spotlight pass ran.
        static let spotlightDate = "diagnostics.spotlight.date"
        /// How many items that pass indexed.
        static let spotlightCount = "diagnostics.spotlight.count"
    }

    // MARK: - Background refresh

    /// Records that a background refresh has begun, and clears the previous run's outcome.
    ///
    /// Leaving the previous end in place would make a run killed halfway read as completed.
    ///
    /// - Parameter date: When it began.
    func backgroundRefreshStarted(at date: Date = .now) {
        defaults.set(date, forKey: Key.backgroundStarted)
        // A new run owns no end yet. Left in place, the previous run's finish
        // would make a run killed halfway read as completed.
        defaults.removeObject(forKey: Key.backgroundFinished)
        defaults.removeObject(forKey: Key.backgroundCompleted)
    }

    /// Records that a background refresh has ended.
    ///
    /// - Parameters:
    ///   - date: When it ended.
    ///   - completed: `false` when iOS's expiration handler ended the task before the work
    ///     was done.
    func backgroundRefreshFinished(at date: Date = .now, completed: Bool) {
        defaults.set(date, forKey: Key.backgroundFinished)
        defaults.set(completed, forKey: Key.backgroundCompleted)
    }

    /// The most recent background refresh, or `nil` when none has run on this device.
    var lastBackgroundRefresh: BackgroundRun? {
        guard let started = defaults.object(forKey: Key.backgroundStarted) as? Date else { return nil }
        guard let finished = defaults.object(forKey: Key.backgroundFinished) as? Date else {
            return BackgroundRun(started: started, finished: nil, outcome: .unfinished)
        }
        return BackgroundRun(started: started, finished: finished,
                             outcome: defaults.bool(forKey: Key.backgroundCompleted) ? .completed : .expired)
    }

    // MARK: - Widgets and Spotlight

    /// Records that the widgets were asked to reload.
    ///
    /// - Parameter date: When they were asked.
    func widgetsReloaded(at date: Date = .now) {
        defaults.set(date, forKey: Key.widgetReload)
    }

    /// When the widgets were last asked to reload, or `nil` when never.
    var lastWidgetReload: Date? {
        defaults.object(forKey: Key.widgetReload) as? Date
    }

    /// Records a Spotlight indexing pass.
    ///
    /// - Parameters:
    ///   - count: How many items were indexed.
    ///   - date: When the pass ran.
    func spotlightIndexed(count: Int, at date: Date = .now) {
        defaults.set(date, forKey: Key.spotlightDate)
        defaults.set(count, forKey: Key.spotlightCount)
    }

    /// The most recent Spotlight pass and how many items it indexed, or `nil` when none has
    /// run.
    var lastSpotlightIndex: (count: Int, date: Date)? {
        guard let date = defaults.object(forKey: Key.spotlightDate) as? Date else { return nil }
        return (defaults.integer(forKey: Key.spotlightCount), date)
    }
}
