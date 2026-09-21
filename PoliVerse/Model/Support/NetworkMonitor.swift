import Foundation
import Network
import Observation
import OSLog

/// The one thing most callers want to know about the network.
///
/// A protocol so that a test can say "offline" without an `NWPathMonitor`,
/// which reports asynchronously and cannot be told what to think.
@MainActor
protocol Reachability: AnyObject, Sendable {
    var isOnline: Bool { get }
}

/// Whether the phone has a usable connection.
///
/// Exists so the app can say "offline" instead of "Impossibile raggiungere i
/// server del Politecnico". Those read as the same sentence to a developer and
/// as completely different ones to a student: the first is their basement, the
/// second is the university being broken.
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    /// True on cellular, so a 150-request room sweep can be offered rather
    /// than performed.
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "network")

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

    deinit { monitor.cancel() }
}

extension NetworkMonitor: Reachability {}

/// A connection that is whatever a test says it is.
@MainActor
final class StubReachability: Reachability {
    var isOnline: Bool

    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }
}
