import Foundation
import Observation

/// Which services have stopped answering, and until when they are left alone.
///
/// A timeout says something about the host, not about the one request that met
/// it: every screen asking that host is about to wait the same fifteen seconds.
/// After ``threshold`` timeouts with no answer in between, the host is paused for
/// ``pause``: requests to it fail at once, so the screens fall back on their stored
/// copies without waiting. The first request after the pause goes through; if it
/// times out too the host is paused again, and any answer at all clears it.
///
/// Values in, decision out: the instant is always given, never read.
nonisolated struct HostBreaker: Sendable {
    /// What noting a request changed.
    enum Change: Equatable, Sendable {
        /// The host is paused from now, for this long.
        case paused(Duration)
        /// The host answered: it is no longer counted as slow.
        case resumed
    }

    /// How many timeouts in a row pause a host.
    var threshold = 2
    /// How long a paused host is left alone.
    var pause: Duration = .seconds(30)

    private var timeouts: [String: Int] = [:]
    private var pausedUntil: [String: ContinuousClock.Instant] = [:]

    /// Creates a breaker with nothing paused.
    ///
    /// - Parameters:
    ///   - threshold: How many timeouts in a row pause a host.
    ///   - pause: How long a paused host is left alone.
    init(threshold: Int = 2, pause: Duration = .seconds(30)) {
        self.threshold = threshold
        self.pause = pause
    }

    /// Whether requests to a host are being answered without being sent.
    ///
    /// - Parameters:
    ///   - host: The service, by name.
    ///   - now: The current instant.
    func isPaused(_ host: String, at now: ContinuousClock.Instant) -> Bool {
        pausedUntil[host].map { now < $0 } ?? false
    }

    /// Notes how a request to a host ended.
    ///
    /// - Parameters:
    ///   - outcome: How it ended. A cancelled request says nothing about the host.
    ///   - host: The service, by name.
    ///   - now: The current instant.
    /// - Returns: What changed for the host, if anything.
    mutating func note(_ outcome: LedgerRequest.Outcome, host: String,
                       at now: ContinuousClock.Instant) -> Change? {
        switch outcome {
        case .cancelled:
            return nil
        case .ok, .failed:
            // An error status is still an answer: the host is there.
            let wasCounted = timeouts[host] != nil || pausedUntil[host] != nil
            timeouts[host] = nil
            pausedUntil[host] = nil
            return wasCounted ? .resumed : nil
        case .timedOut:
            let count = (timeouts[host] ?? 0) + 1
            timeouts[host] = count
            guard count >= threshold else { return nil }
            pausedUntil[host] = now.advanced(by: pause)
            return .paused(pause)
        }
    }
}

/// A request that was not sent because its host is paused.
nonisolated struct HostPaused: LocalizedError, Equatable, Sendable {
    /// The service, by name.
    let host: String

    var errorDescription: String? {
        String(localized: "\(HostPauses.name(of: host)) non risponde. Riprovo tra poco.")
    }
}

/// The services paused right now, for the screens to name.
///
/// The main-actor face of the ``HostBreaker`` inside ``RequestGate``: the gate
/// says when a host is paused and when it answers again, and a pause ends here
/// by itself when its time is up.
@MainActor
@Observable
final class HostPauses {
    /// The app's pauses, written by the app's gate.
    static let shared = HostPauses()

    /// The hosts paused now, by service name.
    private(set) var hosts: Set<String> = []
    @ObservationIgnored private var ending: [String: Task<Void, Never>] = [:]

    /// Notes that a host is paused, or that it answers again.
    ///
    /// - Parameters:
    ///   - host: The service, by name.
    ///   - pause: How long it is paused for, or `nil` when it answered.
    func set(_ host: String, pausedFor pause: Duration?) {
        ending[host]?.cancel()
        ending[host] = nil
        guard let pause else {
            if hosts.contains(host) { hosts.remove(host) }
            return
        }
        if !hosts.contains(host) { hosts.insert(host) }
        ending[host] = Task(name: "pause \(host)") { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled, let self else { return }
            self.ending[host] = nil
            self.hosts.remove(host)
        }
    }

    /// The paused services as the student knows them, sorted, each once.
    var names: [String] {
        Array(Set(hosts.map(Self.name(of:)))).sorted()
    }

    /// What the student calls a service.
    ///
    /// - Parameter host: The service, by the name requests carry.
    nonisolated static func name(of host: String) -> String {
        switch host {
        case "app": String(localized: "Accesso")
        case "iae": String(localized: "Carriera")
        case "agenda": String(localized: "Orario")
        case "libretto": String(localized: "Libretto")
        case "weBeep": "WeBeep"
        case "wsAule", "maps": String(localized: "Aule")
        case "manifesti": String(localized: "Manifesti")
        default: host
        }
    }
}
