import Foundation
import Testing
@testable import PoliVerse

/// The queue that makes an offline change true later.
///
/// Untestable until the composition root was untangled: it held `weBeep`,
/// `careers`, `career` and `courses` as optionals and took a ``Session``, so
/// standing it up meant standing up four services and the Keychain. It now
/// takes an ``Account``, a ``Reachability`` and a way to deliver — which is
/// three things a test can supply in as many lines.
@Suite("Pending changes")
@MainActor
struct PendingChangesTests {
    private func store() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-\(UUID().uuidString)", isDirectory: true))
    }

    private func queue(online: Bool = true, matricola: String? = "111",
                       store: OfflineStore? = nil) -> PendingChanges {
        PendingChanges(account: StubAccount(matricola: matricola),
                       network: StubReachability(isOnline: online),
                       store: store ?? self.store())
    }

    /// Records what it was asked to send, and answers as told.
    private final class Delivery {
        var accepts = true
        private(set) var sent: [PendingAction] = []
        private(set) var confirmed: [PendingAction] = []

        func attach(to pending: PendingChanges) {
            pending.deliver { [self] action in
                sent.append(action)
                return accepts
            } confirmedBy: { [self] action in
                confirmed.append(action)
            }
        }
    }

    @Test("A recorded change is counted and sent on the next flush")
    func sendsWhatWasRecorded() async {
        let pending = queue()
        let delivery = Delivery()
        delivery.attach(to: pending)

        pending.record(.courseFavourite(moodleID: 7, value: true))
        #expect(pending.count == 1)

        await pending.flush()

        #expect(delivery.sent.count == 1)
        #expect(pending.count == 0)
    }

    /// Handing ownership back to the server is the whole reason the caller is
    /// told: keeping the optimistic override would make the app ignore a
    /// favourite removed later from the web, forever.
    @Test("A delivered change is confirmed to whoever was showing it")
    func confirmsDelivery() async {
        let pending = queue()
        let delivery = Delivery()
        delivery.attach(to: pending)

        pending.record(.courseHidden(moodleID: 3, value: true))
        await pending.flush()

        #expect(delivery.confirmed.count == 1)
    }

    /// The default before the composition root registers anything. An
    /// unregistered queue must hold its changes rather than drop them — which
    /// is the failure the four optional model slots used to produce silently.
    @Test("An unregistered queue keeps its changes instead of losing them")
    func unregisteredQueueHolds() async {
        let pending = queue()

        pending.record(.targetAverage(28))
        await pending.flush()

        #expect(pending.count == 1)
    }

    @Test("Nothing is sent while offline")
    func offlineSendsNothing() async {
        let pending = queue(online: false)
        let delivery = Delivery()
        delivery.attach(to: pending)

        pending.record(.courseFavourite(moodleID: 7, value: true))
        await pending.flush()

        #expect(delivery.sent.isEmpty)
        #expect(pending.count == 1)
    }

    /// There is nobody to send on behalf of, and the queue is keyed by
    /// matricola — so a signed-out flush would ask the wrong question.
    @Test("Nothing is sent while signed out")
    func signedOutSendsNothing() async {
        let pending = queue(matricola: nil)
        let delivery = Delivery()
        delivery.attach(to: pending)

        pending.record(.courseFavourite(moodleID: 7, value: true))
        await pending.flush()

        #expect(delivery.sent.isEmpty)
    }

    /// If the network went away again, spending the retry budget of everything
    /// behind the first failure is how a queue empties itself into nothing.
    @Test("A flush stops at the first failure rather than burning the queue")
    func stopsAtFirstFailure() async {
        let pending = queue()
        let delivery = Delivery()
        delivery.attach(to: pending)
        delivery.accepts = false

        pending.record(.courseFavourite(moodleID: 1, value: true))
        pending.record(.courseHidden(moodleID: 2, value: true))
        await pending.flush()

        #expect(delivery.sent.count == 1)
        #expect(delivery.confirmed.isEmpty)
        #expect(pending.count == 2)
    }

    /// A change abandoned during the last session is surfaced at launch, not
    /// only after a flush — otherwise it stays unreported until the queue
    /// happens to run again.
    @Test("Changes survive a relaunch under the same account")
    func survivesRelaunch() async {
        let store = store()
        let first = queue(store: store)
        first.record(.targetAverage(29))
        store.flush()

        let second = queue(store: store)

        #expect(second.count == 1)
    }

    /// One person has a matricola per enrolment; a change queued under one
    /// must not be sent on behalf of the other.
    @Test("Another account's queue is not this account's")
    func queuesAreKeyedByAccount() async {
        let store = store()
        let mine = queue(matricola: "111", store: store)
        mine.record(.targetAverage(29))
        store.flush()

        let theirs = queue(matricola: "222", store: store)

        #expect(theirs.count == 0)
    }
}
