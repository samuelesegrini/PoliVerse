import Foundation
import MetricKit
import StateReporting

/// Tells MetricKit what the app was doing, so a hang or a hitch arrives
/// already attributed: "the Calendar hitches", not "the app hitches".
///
/// iOS 27's StateReporting splits hang time, hitch time, terminations and
/// signpost intervals by the state that was active. Two domains, each a small
/// fixed set of labels, which is what Apple asks for — the number of unique
/// states is limited, and reports flag it when an app goes past it.
///
/// - Tab: the selected tab, reported as it changes.
/// - Data: live or sample data. Demo sessions do no networking and would
///   otherwise flatter every number they are averaged into.
///
/// Apple's sample calls `MetricManager.stateReporter(for:)`, which the iOS 27
/// SDK does not have; `StateReporter.reporter(for:)` is the real entry point
/// (`docs/metrickit-performance.md` §1.8). On iOS 26 everything here is a no-op.
@MainActor
enum PerformanceStates {
    nonisolated enum Domain: String, CaseIterable {
        case tab = "one.wape.PoliVerse.tab"
        case data = "one.wape.PoliVerse.data"
    }

    /// The tabs of the interface the app actually ships: Oggi, Corsi,
    /// Carriera, Cerca. Taken from ``NewDestination/Tab`` rather than written
    /// out again, so the labels in the field can never drift from the tabs on
    /// screen — which is what happened to the five labels the previous
    /// interface reported, kept here long after that interface stopped being
    /// the one students see.
    ///
    /// Anything else is reported as no state rather than as a new one: an
    /// unbounded label set is exactly what the state limit punishes, and an
    /// empty label is a fatal error.
    static let tabs: Set<String> = Set(NewDestination.Tab.allCases.map(\.rawValue))

    private static var lastTab: String??
    private static var lastData: Bool?

    static func tabSelected(_ tab: String?) {
        let label = tab.flatMap { tabs.contains($0) ? $0 : nil }
        // StateReporting is rate-limited to human timescales; a repeated
        // report of the same state spends that budget for nothing.
        guard lastTab != .some(label) else { return }
        lastTab = .some(label)
        guard #available(iOS 27, *) else { return }
        Reporters.tab.reportTransition(to: label)
    }

    static func dataSource(usesSampleData: Bool) {
        guard lastData != usesSampleData else { return }
        lastData = usesSampleData
        guard #available(iOS 27, *) else { return }
        Reporters.data.reportTransition(to: usesSampleData ? "sample" : "live")
    }

    @available(iOS 27, *)
    nonisolated static var enabledDomains: Set<StateReportingDomain> {
        Set(Domain.allCases.map { StateReportingDomain(rawValue: $0.rawValue) })
    }

    /// One reporter per domain for the process: asking again for the same
    /// domain with different metadata types crashes.
    @available(iOS 27, *)
    private enum Reporters {
        static let tab = StateReporter<Never, Never>.reporter(for: Domain.tab.rawValue)
        static let data = StateReporter<Never, Never>.reporter(for: Domain.data.rawValue)
    }
}
