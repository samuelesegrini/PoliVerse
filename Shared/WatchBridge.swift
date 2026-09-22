#if canImport(WatchConnectivity)
import Foundation
import OSLog
import WatchConnectivity

/// The link between the phone and the Watch.
///
/// One type on both sides, because the two halves have to agree on the shape
/// of what crosses and there is no third place to put that agreement. The
/// phone calls ``send(_:)``; the Watch reads ``snapshot``.
///
/// The transport is `updateApplicationContext`, which keeps exactly one value
/// — the latest — and delivers it whenever the other side next runs. That is
/// the right shape here: a snapshot of today is worthless the moment a newer
/// one exists, so a queue of superseded days would only delay the current one.
///
/// Everything fails quietly. An unpaired Watch, an app never installed on it,
/// a session that will not activate: all of them mean the Watch shows what it
/// last knew, which is the state it is in most of the time anyway.
@MainActor @Observable
final class WatchBridge: NSObject {
    /// The one bridge per process.
    static let shared = WatchBridge()

    /// The latest snapshot: received from the phone on the Watch, or last sent
    /// on the phone. `nil` until one arrives.
    private(set) var snapshot: WatchSnapshot?

    /// Diagnostic log for this type, under the `watch` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "watch")

    /// Where the Watch keeps the last snapshot between launches.
    ///
    /// Its own container, not the app group: an app group is shared between
    /// processes on one device, and the Watch is another device.
    private let defaults = UserDefaults.standard

    /// Creates the bridge and restores whatever was last received.
    private override init() {
        super.init()
        if let data = defaults.data(forKey: WatchSnapshot.cacheName) {
            snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
        }
    }

    /// Activates the session, if this device supports one.
    ///
    /// Called from both sides at launch. Safe to call more than once: an
    /// already-activated session ignores it.
    func start() {
        guard WCSession.isSupported() else {
            log.notice("no watch session on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends a snapshot to the other side, replacing any not yet delivered.
    ///
    /// - Parameter snapshot: What the Watch should show.
    func send(_ snapshot: WatchSnapshot) {
        self.snapshot = snapshot
        store(snapshot)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            // Not up yet: the next `start()` will activate, and the caller
            // sends again on its own schedule. Nothing is queued here, because
            // a queued snapshot of today is wrong by tomorrow.
            log.notice("watch session not activated; snapshot not sent")
            return
        }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try session.updateApplicationContext([WatchSnapshot.payloadKey: data])
            log.notice("snapshot sent: \(snapshot.entries.count, privacy: .public) entries")
        } catch {
            log.error("snapshot not sent: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Keeps the snapshot for the next launch.
    ///
    /// - Parameter snapshot: The snapshot to keep.
    private func store(_ snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: WatchSnapshot.cacheName)
    }

    /// Adopts a payload that arrived from the other side.
    ///
    /// - Parameter data: The encoded snapshot, taken out of the context by the
    ///   delegate — `[String: Any]` is not `Sendable` and does not cross.
    private func adopt(_ data: Data) {
        guard let received = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            log.notice("watch context had nothing this build can read")
            return
        }
        snapshot = received
        store(received)
    }
}

/// The session's callbacks, which arrive off the main actor.
extension WatchBridge: WCSessionDelegate {
    /// Notes that the session came up, or did not.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - activationState: What it settled on.
    ///   - error: Why it did not activate, when it did not.
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        // A context may already be waiting from before this launch. Only the
        // `Data` inside it crosses actors: `[String: Any]` is not `Sendable`.
        let data = session.receivedApplicationContext[WatchSnapshot.payloadKey] as? Data
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.adopt(data)
        }
    }

    /// Takes a snapshot that arrived while running.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - applicationContext: The payload.
    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        // `[String: Any]` is not `Sendable`; the payload inside it is `Data`,
        // which is, so only that is carried across.
        let data = applicationContext[WatchSnapshot.payloadKey] as? Data
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.adopt(data)
        }
    }

    #if os(iOS)
    /// Required on iOS, where a Watch can be unpaired and another paired.
    ///
    /// - Parameter session: The session.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Reactivates for the newly paired Watch.
    ///
    /// - Parameter session: The session.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
#endif
