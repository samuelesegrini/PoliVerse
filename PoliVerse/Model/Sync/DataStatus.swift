import Foundation
import Observation

/// The single phrase the app uses to describe the data on screen.
///
/// Collapses six conditions — sample data, no connection, per-service failure, a
/// refresh in flight, a refresh just finished, and everything fine — into one
/// ``State``, one ``summary`` and one ``symbol``, shared by the status line and
/// by Impostazioni so the two cannot disagree.
///
/// ## Staying quiet
///
/// ``State/idle`` draws nothing. A refresh is only announced once it has run for
/// ``quietInterval``, and the confirmation that follows it is only shown if the
/// refresh itself was shown. ``isQuiet`` lets the status line collapse entirely.
///
/// ``FreshnessCoordinator`` drives the instance through ``refreshBegan()`` and
/// ``refreshEnded(failures:at:)``.
@MainActor
@Observable
final class DataStatus {
    /// What the app is showing, in the order of precedence ``DataStatus/state``
    /// applies.
    enum State: Equatable {
        /// Fresh data with nothing in flight. Nothing is shown.
        case idle
        /// A refresh has been running for at least ``DataStatus/quietInterval``.
        case refreshing
        /// A refresh has just finished, with the time it finished at. Held for
        /// ``DataStatus/confirmationInterval``, then back to ``idle``.
        case updated(Date)
        /// No usable connection. What is on screen came from the offline copy.
        case offline
        /// The last pass could not reach one or more services, named here as they appear
        /// on screen.
        case failed([String])
        /// None of the data on screen is the student's own.
        case sample
    }

    /// How long a refresh must run before it is announced. Longer than a load served
    /// out of ``LoadWindow``, shorter than a real round trip.
    static let quietInterval: Duration = .milliseconds(700)
    /// How long ``State/updated(_:)`` is shown before the line goes quiet.
    static let confirmationInterval: Duration = .seconds(3)

    /// When the last pass finished with every service in hand, or `nil` if none has.
    private(set) var lastUpdated: Date?
    /// Services the last pass could not reach, by their name on screen. Empty after
    /// a clean pass or after ``clearFailures()``.
    private(set) var failures: [String] = []

    /// Whether a pass is in flight, whether or not it is being shown.
    private var isRefreshing = false
    /// Whether the pass in flight has outlived ``quietInterval``.
    private var showsRefreshing = false
    /// Whether ``State/updated(_:)`` is currently being shown.
    private var showsConfirmation = false
    /// Waits out ``quietInterval`` before a pass is announced.
    private var quiet: Task<Void, Never>?
    /// Waits out ``confirmationInterval`` before the confirmation is withdrawn.
    private var confirmation: Task<Void, Never>?

    /// Source of ``Session/useMockData`` and of the sign-in state.
    private let session: Session
    /// Source of reachability, which outranks per-service failures.
    private let network: NetworkMonitor
    /// This instance's quiet interval.
    private let quietInterval: Duration
    /// This instance's confirmation interval.
    private let confirmationInterval: Duration

    /// Creates a status for one session.
    ///
    /// - Parameters:
    ///   - session: Supplies the sample-data flag and the sign-in state.
    ///   - network: Supplies reachability.
    ///   - quietInterval: How long a pass must run before it is announced.
    ///     Shortened in tests.
    ///   - confirmationInterval: How long the confirmation is held.
    init(session: Session, network: NetworkMonitor,
         quietInterval: Duration = DataStatus.quietInterval,
         confirmationInterval: Duration = DataStatus.confirmationInterval) {
        self.session = session
        self.network = network
        self.quietInterval = quietInterval
        self.confirmationInterval = confirmationInterval
    }

    /// The single state, by a fixed precedence.
    ///
    /// 1. ``State/sample`` — the only state in which what is on screen is untrue
    ///    rather than merely old.
    /// 2. ``State/offline`` — explains any failures, so it is reported instead of
    ///    them.
    /// 3. ``State/failed(_:)`` — only when an account is signed in; without one
    ///    every service fails at once and the login screen already says why.
    /// 4. ``State/refreshing``, then ``State/updated(_:)``, then ``State/idle``.
    var state: State {
        if session.useMockData { return .sample }
        if !network.isOnline { return .offline }
        // Without an account every service fails at once, and five names in a
        // row is the app blaming the Politecnico for a student who has simply
        // signed out. The login screen already says the true thing there.
        if !failures.isEmpty, hasAccount { return .failed(failures) }
        if showsRefreshing { return .refreshing }
        if showsConfirmation, let lastUpdated { return .updated(lastUpdated) }
        return .idle
    }

    /// Whether a failed load is news about the university rather than the absence of
    /// a session. `false` for ``Session/State/signedOut`` and
    /// ``Session/State/failed(_:)``.
    private var hasAccount: Bool {
        switch session.state {
        case .signedOut, .failed: false
        case .loading, .exchangingCode, .signedIn: true
        }
    }

    /// `true` when there is nothing to say, in which case the status line draws no
    /// space at all.
    var isQuiet: Bool { state == .idle }

    /// A mark on the way in to Impostazioni: ``attention`` for a failure, ``sample``
    /// for sample data.
    enum Badge: Equatable { case attention, sample }

    /// The mark for the way in to Impostazioni, or `nil` for none.
    ///
    /// Only the two states that persist until someone acts are badged. A refresh in
    /// flight and a passing outage resolve themselves.
    var badge: Badge? {
        switch state {
        case .sample: .sample
        case .failed: .attention
        case .idle, .refreshing, .updated, .offline: nil
        }
    }

    // MARK: - Said in one place

    /// The phrase for the current state, shared by the status line and Impostazioni.
    ///
    /// In ``State/idle`` it reports ``lastUpdated`` when there is one, and otherwise
    /// says that nothing has been updated yet.
    var summary: LocalizedStringResource {
        switch state {
        case .sample:
            "Dati di esempio"
        case .offline:
            "Senza connessione"
        case .failed(let services) where services.count == 1:
            "\(services[0]): aggiornamento non riuscito"
        case .failed(let services):
            "Aggiornamento non riuscito per \(services.count) servizi"
        case .refreshing:
            "Aggiornamento in corso…"
        case .updated(let date):
            "Aggiornato alle \(date.formatted(date: .omitted, time: .shortened))"
        case .idle:
            if let lastUpdated {
                "Aggiornato alle \(lastUpdated.formatted(date: .omitted, time: .shortened))"
            } else {
                "Non ancora aggiornato"
            }
        }
    }

    /// The SF Symbol name shown beside ``summary``.
    var symbol: String {
        switch state {
        case .sample: "theatermasks.fill"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        case .refreshing: "arrow.clockwise"
        case .updated, .idle: "checkmark.circle"
        }
    }

    // MARK: - Driven by the coordinator

    /// Records that a pass has started.
    ///
    /// Nothing is shown immediately: the line appears only if the pass outlives
    /// ``quietInterval``. Cancels any pending confirmation.
    func refreshBegan() {
        isRefreshing = true
        showsConfirmation = false
        confirmation?.cancel()
        quiet?.cancel()
        quiet = Task { [weak self] in
            try? await Task.sleep(for: self?.quietInterval ?? DataStatus.quietInterval)
            guard !Task.isCancelled, let self, isRefreshing else { return }
            showsRefreshing = true
        }
    }

    /// Records that a pass has finished.
    ///
    /// ``lastUpdated`` advances only on a clean pass. The confirmation is shown only
    /// if the refresh itself was shown, so a pass the student never waited on passes
    /// silently.
    ///
    /// - Parameters:
    ///   - failures: Services the pass could not reach, by their name on screen.
    ///   - date: When the pass finished.
    func refreshEnded(failures: [String] = [], at date: Date = .now) {
        isRefreshing = false
        quiet?.cancel()
        let wasVisible = showsRefreshing
        showsRefreshing = false
        self.failures = failures
        guard failures.isEmpty else { return }
        lastUpdated = date
        guard wasVisible else { return }
        showsConfirmation = true
        confirmation = Task { [weak self] in
            try? await Task.sleep(for: self?.confirmationInterval ?? DataStatus.confirmationInterval)
            guard !Task.isCancelled, let self else { return }
            showsConfirmation = false
        }
    }

    /// Discards the recorded failures, so a retry starts clean rather than showing
    /// the previous error until the next pass happens to succeed.
    func clearFailures() {
        failures = []
    }
}
