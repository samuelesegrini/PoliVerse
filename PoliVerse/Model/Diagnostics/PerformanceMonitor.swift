import Foundation
import MetricKit
import OSLog

/// Collects everything MetricKit reports about the app in the field.
///
/// Every report — the launch histogram, crashes, hangs, disk writes — is kept on the
/// device by ``ReportArchive`` and sent nowhere: the app has no analytics backend, and
/// adding one would be a poor trade for the student whose data it is.
///
/// Research and sources: `docs/metrickit-performance.md`.
@MainActor
enum PerformanceMonitor {
    /// Diagnostic log for this type, under the `metrics` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "metrics")
    /// Whether ``start()`` has run, so collection begins once.
    private static var started = false

    /// Whether iOS started the process before the student opened the app.
    ///
    /// Worth knowing before reading any launch number: a prewarmed launch has already paid
    /// for dynamic linking and part of the runtime setup, so its measurements are not
    /// comparable with a cold one.
    static var isPrewarmed: Bool {
        ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
    }

    /// Begins MetricKit collection. Call first thing in ``PoliVerseApp/init()``.
    ///
    /// Subscribing during launch is safe and documented as such, and a late subscription is
    /// the one way to lose a report. Repeated calls do nothing.
    static func start() {
        guard !started else { return }
        started = true
        ModernMetricStream.shared.start()
        log.info("MetricKit collection started (prewarmed: \(isPrewarmed, privacy: .public))")
    }

    /// Extends MetricKit's launch measurement over some work, so the number reflects when
    /// the app became usable rather than when it drew a spinner.
    ///
    /// A failure to track is logged and otherwise ignored: work must never move earlier or
    /// wait longer to satisfy a metric.
    ///
    /// - Parameters:
    ///   - id: Names the launch task in the report.
    ///   - work: The work to measure.
    /// - Returns: Whatever the work returned.
    static func trackLaunch<T>(_ id: String, _ work: () async -> T) async -> T {
        await ModernMetricStream.shared.manager.trackLaunchTask(
            id: LaunchTaskID(rawValue: id),
            onTrackingError: { error in
                log.notice("Launch task \(id, privacy: .public) not tracked: \(String(describing: error.reason), privacy: .public)")
            },
            work)
    }
}

/// The `MetricManager` and its two report streams, consumed off the main actor.
///
/// One instance for the process: two managers each receive a non-deterministic subset of
/// reports rather than a full copy. Held for the process lifetime, since the streams
/// stop when the manager goes.
///
/// The state domains are fixed at creation, which is why they are declared in
/// ``PerformanceStates`` rather than where states are reported.
nonisolated final class ModernMetricStream: Sendable {
    /// The one instance for the process.
    static let shared = ModernMetricStream()
    /// The manager both streams come from.
    let manager = MetricManager(enabledStateReportingDomains: PerformanceStates.enabledDomains)

    /// Starts consuming both report streams, storing everything in ``ReportArchive``.
    ///
    /// Detached at utility priority: report delivery is not the student's business.
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
