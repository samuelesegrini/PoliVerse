#if canImport(WatchConnectivity)
import Foundation
import OSLog
import WatchConnectivity
#if os(watchOS)
import WidgetKit
#endif

/// The link between the phone and the Watch.
///
/// One type on both sides, because the two halves have to agree on the shape
/// of what crosses and there is no third place to put that agreement. The
/// phone calls ``send(_:)``; the Watch reads ``snapshot``.
///
/// Two transports, for two kinds of urgency:
///
/// - `updateApplicationContext` keeps exactly one value — the latest — and
///   delivers it whenever the Watch next runs. That is the right shape for a
///   snapshot, which is worthless the moment a newer one exists.
/// - `transferCurrentComplicationUserInfo` wakes the Watch now, but only when
///   one of its complications is on the face, and only a limited number of
///   times a day. It is spent only when what a wrist would see has changed:
///   a complication showing yesterday's room is the one failure a student
///   would actually notice.
///
/// The Watch can also ask. When it comes to the front holding a snapshot
/// older than ``WatchSnapshot/staleAfter``, and the phone is in reach, it
/// sends a message; iOS wakes the phone's app in the background if need be,
/// the phone loads what is due and replies with a fresh snapshot. Nothing to
/// tap: opening the app is the request.
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

    /// Whether the Watch is waiting for the phone to answer a request.
    private(set) var isRefreshing = false

    /// Whether the other side can be messaged right now. On the Watch, the
    /// phone is in reach and the session is up.
    private(set) var isReachable = false

    /// Tells one request from the next, so a request's time-out never ends a
    /// later one.
    private var request = 0

    /// What the phone does when the Watch asks: load what is due and send.
    private var answer: (@MainActor () async -> Void)?

    /// Diagnostic log for this type, under the `watch` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "watch")

    /// Creates the bridge and restores whatever was last kept.
    private override init() {
        super.init()
        snapshot = WatchSnapshotStore.load()
    }

    /// Activates the session, if this device supports one.
    ///
    /// Called from both sides at launch, and on the Watch again when the
    /// system wakes the app for incoming data. Safe to call more than once:
    /// an already-activated session ignores it.
    func start() {
        guard WCSession.isSupported() else {
            log.notice("no watch session on this device")
            return
        }
        let session = WCSession.default
        guard session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }

    /// Sets what the phone does when the Watch asks for a fresh snapshot.
    ///
    /// Set before ``start()``: a request can be what launched the app, and it
    /// arrives as soon as the session is up.
    ///
    /// - Parameter answer: Loads what is due and sends the snapshot.
    func answerRequests(with answer: @escaping @MainActor () async -> Void) {
        self.answer = answer
    }

    /// Asks the phone for a fresh snapshot, when the one held is stale and the
    /// phone is in reach.
    ///
    /// Called whenever the Watch app comes to the front and whenever the phone
    /// comes into reach while it is there. Does nothing on the phone, while a
    /// request is already out, or when the snapshot is recent enough.
    ///
    /// - Parameter date: The moment staleness is judged at.
    func refreshIfStale(at date: Date = .now) {
        #if os(watchOS)
        guard !isRefreshing, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        if let snapshot, !snapshot.needsRefresh(at: date) { return }
        isRefreshing = true
        request += 1
        let current = request
        log.notice("asking the phone for a fresh snapshot")
        // `@Sendable` spelled out: the class is main-actor isolated, and a
        // closure inferred to be would trap when WatchConnectivity calls it
        // on its own queue.
        session.sendMessage([WatchSnapshot.requestKey: true], replyHandler: { @Sendable reply in
            let data = reply[WatchSnapshot.payloadKey] as? Data
            Task { @MainActor [weak self] in
                if let data { self?.adopt(data) }
                self?.finish(current)
            }
        }, errorHandler: { @Sendable error in
            let reason = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.log.notice("request failed: \(reason, privacy: .public)")
                self?.finish(current)
            }
        })
        // WatchConnectivity's own time-out is long; a wrist is not.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.finish(current)
        }
        #endif
    }

    /// Ends a request, unless a later one has started since.
    ///
    /// - Parameter id: The request that ended.
    private func finish(_ id: Int) {
        guard id == request else { return }
        isRefreshing = false
    }

    /// Answers a request from the Watch.
    ///
    /// - Returns: The snapshot to reply with, encoded, or `nil` when the phone
    ///   has nothing to send.
    private func respond() async -> Data? {
        await answer?()
        guard let snapshot else { return nil }
        return try? JSONEncoder().encode(snapshot)
    }

    /// Whether the session still has data on its way in.
    ///
    /// A background wake for WatchConnectivity has to stay alive until this is
    /// `false`, or the system suspends the app with the payload undelivered.
    var hasContentPending: Bool {
        WCSession.isSupported() && WCSession.default.hasContentPending
    }

    /// Sends a snapshot to the other side, replacing any not yet delivered.
    ///
    /// - Parameter snapshot: What the Watch should show.
    func send(_ snapshot: WatchSnapshot) {
        let changed = self.snapshot?.content != snapshot.content
        self.snapshot = snapshot
        WatchSnapshotStore.save(snapshot)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            // Not up yet: the next `start()` will activate, and the caller
            // sends again on its own schedule. Nothing is queued here, because
            // a queued snapshot of today is wrong by tomorrow.
            log.notice("watch session not activated; snapshot not sent")
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        do {
            let data = try JSONEncoder().encode(snapshot)
            let payload = [WatchSnapshot.payloadKey: data]
            try session.updateApplicationContext(payload)
            #if os(iOS)
            if changed, session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
                session.transferCurrentComplicationUserInfo(payload)
                log.notice("complication transfer: \(session.remainingComplicationUserInfoTransfers, privacy: .public) left today")
            }
            #endif
            log.notice("snapshot sent: \(snapshot.entries.count, privacy: .public) entries")
        } catch {
            log.error("snapshot not sent: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adopts a payload that arrived from the other side.
    ///
    /// - Parameter data: The encoded snapshot, taken out of the dictionary by
    ///   the delegate — `[String: Any]` is not `Sendable` and does not cross.
    private func adopt(_ data: Data) {
        guard let received = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            log.notice("watch payload had nothing this build can read")
            return
        }
        // The context and the complication transfer can bring the same
        // snapshot twice, and an older context can land after a newer
        // transfer. Neither should reload the complications or roll them back.
        if let snapshot, snapshot.sentAt >= received.sentAt { return }
        snapshot = received
        WatchSnapshotStore.save(received)
        #if os(watchOS)
        // The complications and the Smart Stack read the store, not this
        // object: they are another process, and learn of the change only here.
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.invalidateRelevance(ofKind: WatchWidgetKind.relevantLecture)
        #endif
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
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
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
        let data = applicationContext[WatchSnapshot.payloadKey] as? Data
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.adopt(data)
        }
    }

    /// Takes a snapshot sent for the complications.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - userInfo: The payload.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let data = userInfo[WatchSnapshot.payloadKey] as? Data
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.adopt(data)
        }
    }

    /// Answers the Watch asking for a fresh snapshot.
    ///
    /// - Parameters:
    ///   - session: The session.
    ///   - message: The request.
    ///   - replyHandler: Sends the reply; must be called, or the Watch waits
    ///     for its time-out.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = Reply(replyHandler)
        guard message[WatchSnapshot.requestKey] != nil else {
            reply([:])
            return
        }
        Task { @MainActor [weak self] in
            let data = await self?.respond()
            reply(data.map { [WatchSnapshot.payloadKey: $0] } ?? [:])
        }
    }

    /// Follows whether the other side can be messaged.
    ///
    /// - Parameter session: The session.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
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
/// A reply handler carried to the main actor and back.
///
/// WatchConnectivity's handler is not `Sendable`, but it is documented as
/// safe to call from any thread, once; the box says so to the compiler.
nonisolated private struct Reply: @unchecked Sendable {
    /// The handler.
    let send: ([String: Any]) -> Void

    /// Wraps a handler.
    ///
    /// - Parameter send: The handler.
    init(_ send: @escaping ([String: Any]) -> Void) { self.send = send }

    /// Sends a reply.
    ///
    /// - Parameter message: The reply.
    func callAsFunction(_ message: [String: Any]) { send(message) }
}
#endif
