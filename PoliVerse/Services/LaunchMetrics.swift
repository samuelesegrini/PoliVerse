import Foundation
import MetricKit
import OSLog

/// Measures launch instead of guessing at it.
///
/// Written after an afternoon of guessing produced one real finding and two
/// false ones. The JSON caches read during `init()` measure about a
/// millisecond each and were not worth touching; the Keychain read in
/// `TokenStore` was, and is now lazy. Neither fact was visible without
/// measuring, so the measurement is now part of the app.
///
/// Two instruments, for two different questions:
///
/// - **Signposts** answer "where did this launch go?" on a device attached to
///   Instruments, with the phases named.
/// - **MetricKit** answers "how long does launch take for real people?",
///   daily, aggregated by the system, with no code on the hot path.
@MainActor
enum LaunchMetrics {
    private static let log = Logger(subsystem: "one.wape.PoliVerse", category: "launch")
    private static let signposter = OSSignposter(
        subsystem: "one.wape.PoliVerse", category: "launch")

    /// Whether iOS started the process ahead of the user opening the app.
    ///
    /// Worth knowing before reading any launch number: a prewarmed launch has
    /// already paid for dynamic linking and some of the runtime setup, so its
    /// measurements are not comparable with a cold one. Mistaking one for the
    /// other is how launch "improvements" get celebrated.
    static var isPrewarmed: Bool {
        ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
    }

    /// Times a named phase of launch.
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        defer { signposter.endInterval(name, state) }
        return try work()
    }

    /// Starts collecting real launch times from the field.
    static func start() {
        MXMetricManager.shared.add(collector)
        log.info("Launch metrics subscribed (prewarmed: \(isPrewarmed, privacy: .public))")
    }

    private static let collector = LaunchMetricCollector()
}

/// Receives MetricKit's daily payloads.
///
/// Reported to the log rather than sent anywhere: the app has no analytics
/// backend, and adding one to measure launch would be a poor trade for the
/// student whose data it would be.
private final class LaunchMetricCollector: NSObject, MXMetricManagerSubscriber {
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "launch")

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let launch = payload.applicationLaunchMetrics else { continue }
            // `optimizedTimeToFirstDraw` is the prewarmed case; the plain one
            // is cold. Logged apart, because averaging them together is
            // exactly the mistake this exists to prevent.
            log.notice("""
                Launch metrics — cold: \(launch.histogrammedTimeToFirstDraw.totalBucketCount, privacy: .public) samples, \
                prewarmed: \(launch.histogrammedOptimizedTimeToFirstDraw.totalBucketCount, privacy: .public) samples, \
                resume: \(launch.histogrammedApplicationResumeTime.totalBucketCount, privacy: .public) samples
                """)
            for bucket in launch.histogrammedTimeToFirstDraw.bucketEnumerator {
                guard let bucket = bucket as? MXHistogramBucket<UnitDuration> else { continue }
                log.notice("  first draw \(bucket.bucketStart.value, privacy: .public)–\(bucket.bucketEnd.value, privacy: .public) ms × \(bucket.bucketCount, privacy: .public)")
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {}
}
