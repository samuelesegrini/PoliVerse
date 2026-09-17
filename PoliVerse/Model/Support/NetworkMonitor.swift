import Foundation
import Network
import Observation
import OSLog

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
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "network")

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
        monitor.start(queue: DispatchQueue(label: "one.wape.PoliVerse.network"))
    }

    deinit { monitor.cancel() }
}
