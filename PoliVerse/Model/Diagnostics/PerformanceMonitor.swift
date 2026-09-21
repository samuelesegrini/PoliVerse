import Foundation
import MetricKit
import OSLog

/// Collects everything MetricKit reports about the app in the field.
///
/// This began as `LaunchMetrics`, written after an afternoon of guessing at
/// launch produced one real finding and two false ones: the JSON caches read
/// during `init()` measured about a millisecond each and were not worth
/// touching; the Keychain read in `TokenStore` was, and is now lazy. Neither
/// fact was visible without measuring, so measuring became part of the app.
///
/// It only read the launch histogram, though, and dropped every crash, hang
/// and disk-write report on the floor. Now every report is kept on the device
/// by ``ReportArchive`` — still sent nowhere: the app has no analytics backend,
/// and adding one would be a poor trade for the student whose data it is.
///
/// iOS 27's `MetricManager`, which replaced `MXMetricManager` and its
/// subscriber. Research and sources: `docs/metrickit-performance.md`.
@MainActor
enum PerformanceMonitor {
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "metrics")
    private static var started = false

    /// Whether iOS started the process ahead of the user opening the app.
    ///
    /// Worth knowing before reading any launch number: a prewarmed launch has
    /// already paid for dynamic linking and some of the runtime setup, so its
    /// measurements are not comparable with a cold one. Mistaking one for the
    /// other is how launch "improvements" get celebrated.
    static var isPrewarmed: Bool {
        ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
    }

    /// Call first thing in `PoliVerseApp.init()`.
    ///
    /// It used to wait for the first frame on the belief that subscribing was
    /// not free. Apple documents the opposite — subscribing is safe during
    /// launch — and a late subscription is the one way to lose a report.
    static func start() {
        guard !started else { return }
        started = true
        ModernMetricStream.shared.start()
        log.info("MetricKit collection started (prewarmed: \(isPrewarmed, privacy: .public))")
    }

    /// Extends MetricKit's launch measurement over `work`, so the number
    /// reflects when the app became usable rather than when it drew a spinner.
    ///
    /// Failures to track are logged and otherwise ignored: work must never
    /// move earlier or wait longer to satisfy a metric.
    static func trackLaunch<T>(_ id: String, _ work: () async -> T) async -> T {
        await ModernMetricStream.shared.manager.trackLaunchTask(
            id: LaunchTaskID(rawValue: id),
            onTrackingError: { error in
                log.notice("Launch task \(id, privacy: .public) not tracked: \(String(describing: error.reason), privacy: .public)")
            },
            work)
    }
}

/// Two async sequences, consumed off the main actor.
///
/// Held for the process lifetime — the streams stop when the manager goes —
/// and one instance only: two managers each receive "a non-deterministic
/// subset of reports rather than a full copy".
///
/// The state domains are fixed at creation, so they are declared here rather
/// than where the states are reported — see ``PerformanceStates``.
nonisolated final class ModernMetricStream: Sendable {
    static let shared = ModernMetricStream()
    let manager = MetricManager(enabledStateReportingDomains: PerformanceStates.enabledDomains)

    func start() {
        let manager = manager
        Task.detached(priority: .utility) {
            for await report in manager.metricReports {
                await ReportArchive.shared.store(report)
            }
        }
        Task.detached(priority: .utility) {
            for await report in manager.diagnosticReports {
                await ReportArchive.shared.store(report)
            }
        }
    }
}
