#if os(iOS)
import BackgroundTasks
#endif
import Foundation
import OSLog

/// Warms the app while it is closed, so opening it shows data rather than a spinner.
///
/// iOS decides whether and when a `BGAppRefreshTask` runs, from how the person
/// actually uses the app, and allows it roughly thirty seconds. So the refresh covers
/// what goes stale and is cheap — the timetable and the career figures — and not the
/// campus-wide room sweep, which is many requests and would be killed half done.
///
/// Every failure here is silent: there is no interface to report to, and a refresh
/// that does not happen simply means the app loads on open.
@MainActor
final class BackgroundRefresh {
    /// The `BGTaskScheduler` identifier, which must also appear in the app's
    /// `BGTaskSchedulerPermittedIdentifiers`.
    static let taskIdentifier = "segrini.samuele.PoliVerse"

    /// Diagnostic log for this type, under the `background` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "background")

#if os(iOS)
    /// Registers the refresh handler.
    ///
    /// Must be called once at launch, before the app finishes launching; registering
    /// later throws. The handler is registered on the main queue, since it hops to the
    /// main actor without checking.
    ///
    /// - Parameter refresh: The work to perform when iOS grants a run.
    func register(refresh: @escaping @Sendable () async -> Void) {
        BGTaskScheduler.shared.register(
            // `.main`, not `nil`: with `nil` the handler runs on a background
            // queue and `assumeIsolated` below aborts.
            forTaskWithIdentifier: Self.taskIdentifier, using: .main
        ) { task in
            MainActor.assumeIsolated {
                self.handle(task, refresh: refresh)
            }
        }
        log.notice("Background refresh registered")
    }

    /// Asks iOS for another run.
    ///
    /// A task is one-shot, so this is called after each run and on entering the
    /// background; not rescheduling would end background refresh permanently. Submission
    /// fails in the simulator and whenever a request is already queued, neither of which
    /// is surfaced.
    ///
    /// - Parameter interval: The earliest the next run may begin, from now.
    func schedule(after interval: TimeInterval = 3600) {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        let log = log
        BGTaskScheduler.shared.submitTaskRequest(request) { error in
            // Fails in the simulator and whenever one is already queued.
            // Neither is worth surfacing.
            if let error {
                log.debug("Could not schedule background refresh: \(error.localizedDescription)")
            }
        }
    }

    /// Runs one granted refresh.
    ///
    /// The next run is queued first, so a run that is killed cannot end background refresh
    /// for good. The start and the outcome are recorded in ``DiagnosticsLog``, since the
    /// unified log is the only other witness. On expiry the work is cancelled cleanly
    /// rather than being terminated mid-write.
    ///
    /// - Parameters:
    ///   - task: The task iOS granted.
    ///   - refresh: The work to perform.
    private func handle(_ task: BGTask, refresh: @escaping @Sendable () async -> Void) {
        // The next one is queued first: if this run is killed, a missed
        // reschedule would end background refresh permanently.
        schedule()

        // Recorded, so the diagnostics page can say when the last run was and
        // whether it finished: the unified log is the only other witness, and
        // nobody reporting a problem can read it.
        DiagnosticsLog.shared.backgroundRefreshStarted()
        let work = Task {
            await refresh()
            // A cancelled run was already recorded by the expiration handler,
            // with the moment iOS stopped it; writing again would move it.
            if !Task.isCancelled {
                DiagnosticsLog.shared.backgroundRefreshFinished(completed: true)
            }
            task.setTaskCompleted(success: true)
        }

        // iOS gives warning before it kills the task. Cancelling cleanly beats
        // being terminated mid-write.
        task.expirationHandler = {
            DiagnosticsLog.shared.backgroundRefreshFinished(completed: false)
            work.cancel()
        }
    }
#else
    /// The scheduler the Mac uses in place of `BGTaskScheduler`, which macOS does not
    /// have. It runs the refresh every half hour, give or take, whenever the system is
    /// idle enough to allow it.
    private var scheduler: NSBackgroundActivityScheduler?

    /// Registers the refresh and starts the periodic run.
    ///
    /// On the Mac the app is usually running, often only in the menu bar, so the refresh
    /// keeps the menu bar panel current rather than warming a closed app.
    ///
    /// - Parameter refresh: The work to perform when macOS grants a run.
    func register(refresh: @escaping @Sendable () async -> Void) {
        let scheduler = NSBackgroundActivityScheduler(identifier: Self.taskIdentifier)
        scheduler.repeats = true
        scheduler.interval = 30 * 60
        scheduler.tolerance = 5 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in
                DiagnosticsLog.shared.backgroundRefreshStarted()
                await refresh()
                DiagnosticsLog.shared.backgroundRefreshFinished(completed: true)
                completion(.finished)
            }
        }
        self.scheduler = scheduler
        log.notice("Background refresh registered")
    }

    /// Does nothing on the Mac: the scheduler set up by ``register(refresh:)`` repeats by
    /// itself.
    ///
    /// - Parameter interval: Ignored.
    func schedule(after interval: TimeInterval = 3600) {}
#endif
}
