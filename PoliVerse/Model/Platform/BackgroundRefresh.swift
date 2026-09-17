import BackgroundTasks
import Foundation
import OSLog

/// Warms the app while it is closed, so opening it shows data rather than a
/// spinner.
///
/// `BGAppRefreshTask` is the right tool and its limits are worth stating
/// plainly, because they shape what is attempted: iOS decides **if** and
/// **when** it runs, based on how the person actually uses the app, and gives
/// it around thirty seconds. So this refreshes the two things that go stale
/// and are cheap — the timetable and the career figures — and does not touch
/// the campus-wide room pass, which is 150 requests and would be killed
/// half-done.
///
/// Every failure mode here is silent by design: there is no UI to report to,
/// and a refresh that does not happen simply means the app loads on open, as
/// it always did.
@MainActor
final class BackgroundRefresh {
    static let taskIdentifier = "one.wape.PoliVerse.refresh"

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "background")

    /// Registered once, at launch, before the app finishes launching —
    /// registering later throws.
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

    /// Asks for another run. Called after each refresh and on entering the
    /// background: a task is one-shot, so not rescheduling means it never runs
    /// again.
    func schedule(after interval: TimeInterval = 3600) {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Fails in the simulator and whenever one is already queued.
            // Neither is worth surfacing.
            log.debug("Could not schedule background refresh: \(error.localizedDescription)")
        }
    }

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
}
