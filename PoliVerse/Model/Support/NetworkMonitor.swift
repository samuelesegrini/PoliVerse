import Foundation
import Network
import Observation
import OSLog

/// Whether the device has a usable connection.
///
/// A protocol so that a test can assert offline behaviour without an
/// `NWPathMonitor`, which reports asynchronously and cannot be told what to think.
/// ``NetworkMonitor`` conforms; ``StubReachability`` serves tests and previews.
@MainActor
protocol Reachability: AnyObject, Sendable {
    /// `true` when a network path is available.
    var isOnline: Bool { get }
}

/// Live reachability, backed by `NWPathMonitor`.
///
/// Lets the app distinguish “offline” from “the Politecnico is unreachable”, which
/// read alike to a developer and mean entirely different things to a student.
/// Observable, so views update as the path changes.
@Observable
final class NetworkMonitor {
    /// `true` when a network path is available.
    ///
    /// Starts optimistic: `NWPathMonitor` reports asynchronously, so a first frame
    /// claiming offline would be wrong more often than right.
    private(set) var isOnline = true
    /// `true` on a metered path, so a sweep of many requests can be offered rather
    /// than performed.
    private(set) var isExpensive = false

    /// The system path monitor, cancelled on deinit.
    private let monitor = NWPathMonitor()
    /// Diagnostic log for this type, under the `network` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "network")

    /// Starts monitoring on a private queue and publishes changes on the main actor.
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                if online != self.isOnline {
                    self.log.notice("network \(online ? "up" : "down", privacy: .public)")
                }
                self.isOnline = online
                self.isExpensive = path.isExpensive
            }
        }
        // Starts optimistic: `NWPathMonitor` reports asynchronously, and a
        // first frame claiming "offline" before the first callback would be
        // a lie more often than not.
        monitor.start(queue: DispatchQueue(label: "segrini.samuele.PoliVerse.network"))
    }

    /// Stops monitoring.
    deinit { monitor.cancel() }
}

/// Live reachability satisfies the protocol as it stands.
extension NetworkMonitor: Reachability {}

/// Reachability that is whatever a test says it is.
@MainActor
final class StubReachability: Reachability {
    /// The value to report. Settable at any time.
    var isOnline: Bool

    /// Creates a stub.
    ///
    /// - Parameter isOnline: The value to report.
    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }
}
