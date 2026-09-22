import Foundation
import Observation
import OSLog

/// Delivers the changes made while offline, once there is signal again.
///
/// The UI applies a change immediately and this type makes it true afterwards, so
/// a tap never waits on a round trip. ``record(_:)`` stores the change in an
/// ``ActionQueue``, ``flush()`` sends what is waiting, and ``failed`` carries
/// whatever the Politecnico refused for good.
///
/// How a change is actually sent is supplied by the composition root through
/// ``deliver(by:confirmedBy:)``. Until that is called, every delivery reports
/// failure, so an unregistered instance holds its changes rather than dropping
/// them.
@Observable
final class PendingChanges {
    /// How many changes are waiting to be sent.
    private(set) var count = 0
    /// Changes the Politecnico refused until their retry budget ran out.
    ///
    /// Surfaced rather than dropped silently, and read at init as well as after a
    /// flush so that a loss from the previous session is still reported.
    private(set) var failed: [PendingAction] = []
    /// `true` while ``flush()`` is sending. A second flush returns immediately.
    private(set) var isFlushing = false

    /// Supplies the matricola, which keys the queue and says whether there is anyone
    /// to send on behalf of.
    private let account: any Account
    /// Consulted before a flush; offline, nothing is attempted.
    private let network: any Reachability
    /// Where the queue is kept. Injectable so that a test cannot enqueue into the
    /// student's own queue.
    private let store: OfflineStore
    /// Diagnostic log for this type, under the `queue` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "queue")

    /// Delivers one queued change. `false` means it could not be delivered, so the
    /// queue keeps it and charges it one attempt.
    typealias Send = @MainActor (PendingAction) async -> Bool
    /// Called once a change has been accepted, so that whoever was showing it
    /// optimistically can hand ownership back to the server.
    typealias Confirm = @MainActor (PendingAction) -> Void

    /// How changes are delivered. Refuses everything until
    /// ``deliver(by:confirmedBy:)`` supplies the real implementation.
    private var send: Send = { _ in false }
    /// What to tell after a change is accepted. Does nothing by default.
    private var confirm: Confirm = { _ in }

    /// Creates the queue's owner and reads what is already waiting.
    ///
    /// - Parameters:
    ///   - account: Supplies the matricola the queue is keyed by.
    ///   - network: Consulted before each flush.
    ///   - store: Where the queue is kept.
    init(account: any Account, network: any Reachability,
         store: OfflineStore = .shared) {
        self.account = account
        self.network = network
        self.store = store
        refresh()
    }

    /// Supplies how a queued change is delivered, and what to tell afterwards.
    ///
    /// The services that perform these writes also record changes into this queue, so
    /// the dependency runs both ways. It is closed here, at one named call in the
    /// composition root, rather than by holding each service as a mutable optional.
    ///
    /// - Parameters:
    ///   - send: Delivers one change; `false` keeps it queued.
    ///   - confirm: Called after a change is accepted.
    func deliver(by send: @escaping Send, confirmedBy confirm: @escaping Confirm = { _ in }) {
        self.send = send
        self.confirm = confirm
    }

    /// Re-reads how many changes are waiting and which were abandoned.
    ///
    /// Called at init as well as after a flush, so a change abandoned in a previous
    /// session is reported at launch rather than waiting for the next flush.
    func refresh() {
        let queue = queue()
        count = queue.pending.count
        failed = queue.abandoned
    }

    /// Opens the queue file for the current account. Each call re-reads from disk.
    private func queue() -> ActionQueue {
        ActionQueue(store: store, account: account.matricola)
    }

    /// Queues a change for delivery. Call it after applying the change locally.
    ///
    /// - Parameter action: The change to deliver.
    func record(_ action: PendingAction) {
        var queue = queue()
        queue.enqueue(action)
        count = queue.pending.count
        log.notice("queued: \(action.label, privacy: .public) (\(self.count, privacy: .public) in attesa)")
    }

    /// Sends everything waiting, oldest first.
    ///
    /// Returns immediately when a flush is already running, when there is no
    /// connection, when nobody is signed in, or when the queue is empty.
    ///
    /// Deliveries are sequential: two queued changes can target the same course, and
    /// sending them together would leave the final state to whichever request the
    /// server happened to handle last. The first failure stops the pass, so a
    /// connection that drops again does not spend the retry budget of everything
    /// behind it.
    func flush() async {
        guard !isFlushing, network.isOnline, account.matricola != nil else { return }
        var queue = queue()
        guard !queue.isEmpty else { return }

        isFlushing = true
        defer { isFlushing = false }

        for action in queue.pending {
            let sent = await send(action)
            if sent {
                queue.remove(action)
                // The override exists only while the change is unsent.
                confirm(action)
            } else {
                queue.recordFailure(action)
                // Stop at the first failure: if the network went away again,
                // spending the retry budget of everything behind it is how a
                // queue empties itself into nothing.
                break
            }
        }

        count = queue.pending.count
        failed = queue.abandoned
        if !failed.isEmpty {
            log.error("\(self.failed.count, privacy: .public) modifiche non inviate")
        }
    }

    /// Re-queues the abandoned changes with a fresh budget and flushes.
    ///
    /// An abandoned change whose target already has something waiting is dropped
    /// rather than re-queued, since re-queueing would replace the student's later
    /// decision with the older value.
    func retryFailures() async {
        var queue = queue()
        let waiting = Set(queue.pending.map(\.targetKey))
        for action in queue.abandoned where !waiting.contains(action.targetKey) {
            queue.enqueue(action)
        }
        queue.clearAbandoned()
        refresh()
        await flush()
    }

    /// Discards the abandoned changes without retrying them, and stops reporting
    /// them.
    func acknowledgeFailures() {
        var queue = queue()
        queue.clearAbandoned()
        failed = []
        count = queue.pending.count
    }

}
