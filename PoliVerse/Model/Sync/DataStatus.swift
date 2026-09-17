import Foundation
import Observation

/// One sentence about the data on screen, for every place that has to say it.
///
/// Three different facts used to be told in three different voices: sample
/// data shouted from a yellow banner above every tab, a refresh in flight said
/// nothing at all, and a load that failed left the last good data on screen
/// with no mark on it. A student could not tell "old" from "invented" from
/// "the Politecnico is down", which are the three things they actually need to
/// tell apart.
///
/// Modelled on how Photos reports iCloud: the status is **one** phrase, it
/// lives in the flow of the content rather than in the chrome, it is **silent
/// while everything is fine**, and the detail — per service, with the last
/// time each worked — lives in Impostazioni. A refresh that takes less than
/// ``quietInterval`` says nothing, because a line that flashes on every tab
/// change is a line people stop reading.
@MainActor
@Observable
final class DataStatus {
    /// What the app is showing, in the order it matters.
    enum State: Equatable {
        /// Fresh data, nothing in flight: say nothing.
        case idle
        /// A refresh has been running long enough to be worth mentioning.
        case refreshing
        /// A refresh has just finished; shown briefly, then back to `idle`.
        case updated(Date)
        /// No usable connection. What is on screen is whatever was cached.
        case offline
        /// The last pass could not reach one or more services, named here.
        case failed([String])
        /// None of this is the student's data.
        case sample
    }

    /// How long a refresh must run before it is worth saying so. Comfortably
    /// longer than a load served from ``LoadWindow``, short enough that a real
    /// round trip is announced before the student wonders.
    static let quietInterval: Duration = .milliseconds(700)
    /// How long "Aggiornato ora" stays before the line goes quiet.
    static let confirmationInterval: Duration = .seconds(3)

    /// When the last pass finished with everything in hand.
    private(set) var lastUpdated: Date?
    /// Services the last pass could not reach, by their name on screen.
    private(set) var failures: [String] = []

    private var isRefreshing = false
    private var showsRefreshing = false
    private var showsConfirmation = false
    private var quiet: Task<Void, Never>?
    private var confirmation: Task<Void, Never>?

    private let session: Session
    private let network: NetworkMonitor
    private let quietInterval: Duration
    private let confirmationInterval: Duration

    /// - Parameters:
    ///   - quietInterval: shortened in tests, which would otherwise spend a
    ///     second of wall clock waiting for a line to appear.
    init(session: Session, network: NetworkMonitor,
         quietInterval: Duration = DataStatus.quietInterval,
         confirmationInterval: Duration = DataStatus.confirmationInterval) {
        self.session = session
        self.network = network
        self.quietInterval = quietInterval
        self.confirmationInterval = confirmationInterval
    }

    /// The one state, by a fixed precedence.
    ///
    /// Sample data first, because it is the only state in which what is on
    /// screen is *false* rather than merely old — and being offline or behind
    /// is beside the point when none of it is real anyway. Offline before
    /// failures, because "senza connessione" explains the failures and blaming
    /// the university for the student's basement is the exact confusion
    /// ``NetworkMonitor`` exists to avoid.
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

    /// Whether a failed load is the university's news or just the absence of
    /// a session.
    private var hasAccount: Bool {
        switch session.state {
        case .signedOut, .failed: false
        case .loading, .exchangingCode, .signedIn: true
        }
    }

    /// Nothing worth saying: the status line draws no space at all.
    var isQuiet: Bool { state == .idle }

    /// Whether the way in to Impostazioni should carry a mark, and which.
    ///
    /// Only the two states that persist until someone acts: a failure, and
    /// sample data. A refresh in flight and a passing outage resolve
    /// themselves, and a badge that comes and goes on its own trains people
    /// to ignore it.
    enum Badge: Equatable { case attention, sample }

    var badge: Badge? {
        switch state {
        case .sample: .sample
        case .failed: .attention
        case .idle, .refreshing, .updated, .offline: nil
        }
    }

    // MARK: - Said in one place

    /// The phrase, shared by the status line and Impostazioni so the two can
    /// never contradict each other.
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

    /// The symbol beside the phrase.
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

    /// A pass has started. Nothing is shown yet: the line only appears if the
    /// pass outlives ``quietInterval``.
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

    /// A pass has finished, with whatever it could not reach.
    ///
    /// The confirmation only appears if the refresh itself did. Saying
    /// "Aggiornato alle 14:32" after a pass nobody was shown is the app
    /// congratulating itself for work the student never waited on.
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

    /// Forgets a failure, so a retry starts from a clean sheet rather than
    /// showing the old error until the next pass happens to succeed.
    func clearFailures() {
        failures = []
    }
}
