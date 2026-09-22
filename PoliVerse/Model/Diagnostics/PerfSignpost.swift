import MetricKit
import OSLog

/// Names the few stretches of work worth timing, for two audiences at once.
///
/// - Instruments, through Points of Interest: where a second went, on a phone on the
///   desk.
/// - MetricKit, through `mxSignpost`: how long the work takes for real students, with
///   CPU, memory and disk writes attached. An interval still open when something goes
///   wrong also rides along in hang and crash reports, so the name says what the app was
///   doing.
///
/// The system caps how many custom signpost metrics it keeps, so ``Name`` is short and
/// fixed. `mxSignpost` pairs begin and end by name, so a name must never be open twice
/// at once; each caller guards for that.
///
/// See `docs/metrickit-performance.md` §1.5.
nonisolated enum PerfSignpost {
    /// The stretches of work that are timed.
    enum Name: String {
        /// ``LoginFlow/restore()``, from launch to a decided session.
        case sessionRestore = "session.restore"
        /// ``AgendaModel/load(around:force:)``.
        case agendaLoad = "agenda.load"
        /// A whole ``CareerSource`` fetch, all six calls.
        case careerLoad = "career.load"
        /// One ``FreshnessCoordinator/revalidate(force:)`` pass.
        case freshnessRevalidate = "freshness.revalidate"
        /// One granted ``BackgroundRefresh`` run.
        case backgroundRefresh = "background.refresh"

        /// The same name as a `StaticString`, which both signpost APIs require.
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

    /// One open interval. Hand it to ``PerfSignpost/end(_:)``, usually through `defer`.
    struct Interval {
        /// What is being timed, so ``PerfSignpost/end(_:)`` closes the right pair.
        fileprivate let name: Name
        /// The Points of Interest interval to close.
        fileprivate let state: OSSignpostIntervalState
    }

    /// The Points of Interest signposter Instruments reads.
    private static let signposter = OSSignposter(
        subsystem: "segrini.samuele.PoliVerse", category: .pointsOfInterest)

    /// The MetricKit log handle `mxSignpost` writes to.
    private static let metricLog = MetricManager.logHandle(category: "PoliVerse")

    /// Opens an interval on both signposters.
    ///
    /// - Parameter name: What is being timed. Must not already be open.
    /// - Returns: The interval to close with ``end(_:)``.
    static func begin(_ name: Name) -> Interval {
        mxSignpost(.begin, log: metricLog, name: name.staticName)
        let state = signposter.beginInterval(name.staticName, id: signposter.makeSignpostID())
        return Interval(name: name, state: state)
    }

    /// Closes an interval on both signposters.
    ///
    /// - Parameter interval: What ``begin(_:)`` returned.
    static func end(_ interval: Interval) {
        signposter.endInterval(interval.name.staticName, interval.state)
        mxSignpost(.end, log: metricLog, name: interval.name.staticName)
    }
}
