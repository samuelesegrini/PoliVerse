import Foundation
import MetricKit
import StateReporting

/// Tells MetricKit what the app was doing, so a hang or a hitch arrives already
/// attributed to a screen rather than to the app as a whole.
///
/// StateReporting splits hang time, hitch time, terminations and signpost intervals by
/// the state that was active. Two domains, each a small fixed set of labels, because the
/// number of unique states is limited and reports flag an app that goes past it:
///
/// - ``Domain/tab``: the selected tab.
/// - ``Domain/data``: live or sample data. A sample session does no networking and would
///   otherwise flatter every number it is averaged into.
///
/// See `docs/metrickit-performance.md` §1.8.
@MainActor
enum PerformanceStates {
    /// The state domains this app reports.
    nonisolated enum Domain: String, CaseIterable {
        /// Which tab is selected.
        case tab = "segrini.samuele.PoliVerse.tab"
        /// Whether the app is showing live or sample data.
        case data = "segrini.samuele.PoliVerse.data"
    }

    /// The tab labels that may be reported: ``NewDestination/Tab``'s, plus `single` for the
    /// single-page layout.
    ///
    /// Anything else is reported as no state rather than as a new one — an unbounded label
    /// set is what the state limit punishes, and an empty label is fatal.
    static let tabs: Set<String> = ["today", "courses", "career", "search", "single"]

    /// The last tab reported, so the same state is not reported twice. Doubly optional: not
    /// yet reported differs from reported as no state.
    private static var lastTab: String??
    /// The last data source reported, so the same state is not reported twice.
    private static var lastData: Bool?

    /// Reports which tab is now selected.
    ///
    /// StateReporting is rate-limited to human timescales, so repeating the current state is
    /// skipped.
    ///
    /// - Parameter tab: The tab's label, or `nil` for no state. A label outside ``tabs`` is
    ///   reported as no state.
    static func tabSelected(_ tab: String?) {
        let label = tab.flatMap { tabs.contains($0) ? $0 : nil }
        // StateReporting is rate-limited to human timescales; a repeated
        // report of the same state spends that budget for nothing.
        guard lastTab != .some(label) else { return }
        lastTab = .some(label)
        Reporters.tab.reportTransition(to: label)
    }

    /// Reports whether the app is showing live or sample data.
    ///
    /// - Parameter usesSampleData: `true` for sample data.
    static func dataSource(usesSampleData: Bool) {
        guard lastData != usesSampleData else { return }
        lastData = usesSampleData
        Reporters.data.reportTransition(to: usesSampleData ? "sample" : "live")
    }

    /// Every domain, for the `MetricManager` that must be created with them.
    nonisolated static var enabledDomains: Set<StateReportingDomain> {
        Set(Domain.allCases.map { StateReportingDomain(rawValue: $0.rawValue) })
    }

    /// One reporter per domain for the whole process: asking again for the same domain with
    /// different metadata types crashes.
    private enum Reporters {
        /// The tab domain's reporter.
        static let tab = StateReporter<Never, Never>.reporter(for: Domain.tab.rawValue)
        /// The data-source domain's reporter.
        static let data = StateReporter<Never, Never>.reporter(for: Domain.data.rawValue)
    }
}
