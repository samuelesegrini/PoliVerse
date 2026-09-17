import MetricKit
import OSLog

/// Names the few stretches of work worth timing, for two audiences at once.
///
/// - **Instruments**, through Points of Interest: where did this second go,
///   on a phone on the desk.
/// - **MetricKit**, through `mxSignpost`: how long does it take for real
///   students, with CPU, memory and disk writes attached, in the daily report.
///   Open intervals also ride along in hang and crash reports, so a good name
///   says what the app was doing when it went wrong.
///
/// The system caps how many custom signpost metrics it keeps, so the list is
/// short and fixed on purpose — `docs/metrickit-performance.md`, Step 1.5.
/// `mxSignpost` pairs begin and end by name, so a name must never be open
/// twice at once: each one below sits behind a guard that makes that so.
nonisolated enum PerfSignpost {
    enum Name: String {
        case sessionRestore = "session.restore"
        case agendaLoad = "agenda.load"
        case careerLoad = "career.load"
        case freshnessRevalidate = "freshness.revalidate"
        case backgroundRefresh = "background.refresh"

        /// `StaticString`, because both signpost APIs insist on one.
        var staticName: StaticString {
            switch self {
            case .sessionRestore: "session.restore"
            case .agendaLoad: "agenda.load"
            case .careerLoad: "career.load"
            case .freshnessRevalidate: "freshness.revalidate"
            case .backgroundRefresh: "background.refresh"
            }
        }
    }

    struct Interval {
        fileprivate let name: Name
        fileprivate let state: OSSignpostIntervalState
    }

    private static let signposter = OSSignposter(
        subsystem: "one.wape.PoliVerse", category: .pointsOfInterest)

    private static let metricLog: OSLog = {
        if #available(iOS 27, *) {
            MetricManager.logHandle(category: "PoliVerse")
        } else {
            MXMetricManager.makeLogHandle(category: "PoliVerse")
        }
    }()

    /// Pair with ``end(_:)``, usually through `defer`.
    static func begin(_ name: Name) -> Interval {
        mxSignpost(.begin, log: metricLog, name: name.staticName)
        let state = signposter.beginInterval(name.staticName, id: signposter.makeSignpostID())
        return Interval(name: name, state: state)
    }

    static func end(_ interval: Interval) {
        signposter.endInterval(interval.name.staticName, interval.state)
        mxSignpost(.end, log: metricLog, name: interval.name.staticName)
    }
}
