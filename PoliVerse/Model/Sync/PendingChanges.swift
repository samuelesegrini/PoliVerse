import Foundation
import Observation
import OSLog

/// Sends the changes made while offline, once there is signal again.
///
/// Optimistic by design: the UI applies a change immediately and this makes it
/// true later. That is the right order for a phone — waiting on a round trip
/// to move a star makes the app feel broken on a train — but it means the
/// change has to be *remembered* rather than hoped for, which is what the
/// queue is.
@Observable
final class PendingChanges {
    private(set) var count = 0
    /// Changes the Politecnico kept refusing. Surfaced rather than dropped
    /// silently: a star that quietly un-stars itself three launches later is
    /// worse than being told.
    private(set) var failed: [PendingAction] = []
    private(set) var isFlushing = false

    /// Only the matricola is wanted, to key the queue and to know whether
    /// there is anyone to send on behalf of — see ``Account``.
    private let account: any Account
    private let network: any Reachability
    /// Where the queue itself is kept. Injectable so a test cannot enqueue
    /// into the student's real one.
    private let store: OfflineStore
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "queue")

    /// How a queued change is actually sent. False means it could not be
    /// delivered, so the queue keeps it and tries again later.
    typealias Send = @MainActor (PendingAction) async -> Bool
    /// Called once a change has been accepted, so whoever was showing it
    /// optimistically can hand ownership back to the server.
    typealias Confirm = @MainActor (PendingAction) -> Void

    /// Refusing everything until the composition root says otherwise is the
    /// safe default: an unregistered queue holds its changes rather than
    /// dropping them.
    private var send: Send = { _ in false }
    private var confirm: Confirm = { _ in }

    init(account: any Account, network: any Reachability,
         store: OfflineStore = .shared) {
        self.account = account
        self.network = network
        self.store = store
        refresh()
    }

    /// Says how to deliver a change, and what to tell afterwards.
    ///
    /// ## Why this is a function and not four properties
    ///
    /// The queue used to hold `weBeep`, `careers`, `career` and `courses` as
    /// optionals, assigned by the app after everything was built. That made a
    /// type-level cycle — the services need the queue to record a change, the
    /// queue needed the services to send it — and it made this class
    /// impossible to construct in a test without constructing all four.
    ///
    /// Worse, it failed silently. `careers` was never assigned at all, so a
    /// queued `.favouriteCareer` could never have been delivered; nobody
    /// noticed because nothing enqueues one yet. A slot that is nil by
    /// accident looks exactly like a slot that is nil on purpose.
    ///
    /// The cycle is real and cannot be removed — it is broken here instead, at
    /// one named place, where forgetting to call it is one mistake rather than
    /// four.
    func deliver(by send: @escaping Send, confirmedBy confirm: @escaping Confirm = { _ in }) {
        self.send = send
        self.confirm = confirm
    }

    /// Reads what is waiting and what was lost.
    ///
    /// Losses are surfaced at launch, not only after a flush: a change
    /// abandoned during the last session would otherwise stay unreported
    /// until the next time the queue happened to run.
    func refresh() {
        let queue = queue()
        count = queue.pending.count
        failed = queue.abandoned
    }

    private func queue() -> ActionQueue {
        ActionQueue(store: store, account: account.matricola)
    }

    /// Records a change to be sent. Call *after* applying it locally.
    func record(_ action: PendingAction) {
        var queue = queue()
        queue.enqueue(action)
        count = queue.pending.count
        log.notice("queued: \(action.label, privacy: .public) (\(self.count, privacy: .public) in attesa)")
    }

    /// Sends everything waiting, oldest first.
    ///
    /// Sequential on purpose. These are small writes against one service, and
    /// two of them can target the same course — sending them at once would
    /// leave the final state up to whichever request the server handled last.
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

    /// Puts abandoned changes back in the queue with a fresh budget and tries
    /// again: for the student who has fixed whatever made the Politecnico
    /// refuse them — usually by signing in again.
    ///
    /// A change whose target has something newer waiting is dropped, not
    /// retried: `enqueue` replaces by target, so retrying it would put the
    /// old value back over the student's later decision.
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

    func acknowledgeFailures() {
        var queue = queue()
        queue.clearAbandoned()
        failed = []
        count = queue.pending.count
    }

}
