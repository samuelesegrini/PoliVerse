import Foundation
import Testing
@testable import PoliVerse

/// Changes made without signal.
///
/// Four operations in the app write to the Politecnico: favouriting a WeBeep
/// course, hiding one, setting a target average, and choosing a favourite
/// career. Offline, each failed silently and the UI reverted — the user's tap
/// was simply undone, with no explanation and nothing to retry.
@Suite("Action queue")
struct ActionQueueTests {
    private func queue() -> ActionQueue {
        ActionQueue(store: OfflineStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("queue-\(UUID().uuidString)", isDirectory: true)),
            account: "10812345")
    }

    private let favourite = PendingAction.courseFavourite(moodleID: 42, value: true)
    private let unfavourite = PendingAction.courseFavourite(moodleID: 42, value: false)

    @Test("An action is queued and comes back")
    func enqueue() {
        var queue = queue()
        queue.enqueue(favourite)
        #expect(queue.pending.count == 1)
        #expect(queue.pending.first == favourite)
    }

    /// The behaviour that makes this worth building rather than retrying
    /// blindly: five taps on a star offline are one request, with the value
    /// the user settled on.
    @Test("Repeated changes to one thing collapse to the last")
    func coalesces() {
        var queue = queue()
        for value in [true, false, true, false, true] {
            queue.enqueue(.courseFavourite(moodleID: 42, value: value))
        }
        #expect(queue.pending.count == 1)
        #expect(queue.pending.first == .courseFavourite(moodleID: 42, value: true))
    }

    /// Coalescing must be per target, or favouriting one course would discard
    /// the change to another.
    @Test("Different targets are kept apart")
    func perTarget() {
        var queue = queue()
        queue.enqueue(.courseFavourite(moodleID: 1, value: true))
        queue.enqueue(.courseFavourite(moodleID: 2, value: true))
        #expect(queue.pending.count == 2)
    }

    /// Favouriting and hiding the same course are different things and both
    /// must survive.
    @Test("Different kinds on one course are both kept")
    func perKind() {
        var queue = queue()
        queue.enqueue(.courseFavourite(moodleID: 42, value: true))
        queue.enqueue(.courseHidden(moodleID: 42, value: true))
        #expect(queue.pending.count == 2)
    }

    @Test("Order is preserved for unrelated actions")
    func ordering() {
        var queue = queue()
        queue.enqueue(.courseFavourite(moodleID: 1, value: true))
        queue.enqueue(.targetAverage(27.5))
        queue.enqueue(.courseHidden(moodleID: 2, value: true))
        #expect(queue.pending.count == 3)
        #expect(queue.pending.first == .courseFavourite(moodleID: 1, value: true))
        #expect(queue.pending.last == .courseHidden(moodleID: 2, value: true))
    }

    /// Coalescing keeps the *original* position, so a change made first does
    /// not jump ahead of one made after it.
    @Test("A coalesced action keeps its place in the queue")
    func coalescingKeepsPosition() {
        var queue = queue()
        queue.enqueue(.courseFavourite(moodleID: 1, value: true))
        queue.enqueue(.targetAverage(27))
        queue.enqueue(.courseFavourite(moodleID: 1, value: false))
        #expect(queue.pending.map(\.targetKey) == ["course-fav-1", "target"])
    }

    @Test("The queue survives a relaunch")
    func persists() {
        let store = OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-\(UUID().uuidString)", isDirectory: true))
        var first = ActionQueue(store: store, account: "1")
        first.enqueue(favourite)

        let second = ActionQueue(store: store, account: "1")
        #expect(second.pending == [favourite])
    }

    /// One person's queued changes must not be sent under another's token.
    @Test("Queues do not leak between accounts")
    func perAccount() {
        let store = OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-\(UUID().uuidString)", isDirectory: true))
        var mine = ActionQueue(store: store, account: "111")
        mine.enqueue(favourite)
        let theirs = ActionQueue(store: store, account: "222")
        #expect(theirs.pending.isEmpty)
    }

    @Test("A completed action leaves the queue")
    func complete() {
        var queue = queue()
        queue.enqueue(favourite)
        queue.remove(favourite)
        #expect(queue.pending.isEmpty)
    }

    /// A change the server keeps refusing must not be retried forever: it
    /// would run on every launch, for every future launch, silently.
    @Test("An action is abandoned after repeated failures")
    func givesUp() {
        var queue = queue()
        queue.enqueue(favourite)
        for _ in 0..<ActionQueue.maxAttempts {
            #expect(!queue.pending.isEmpty)
            queue.recordFailure(favourite)
        }
        #expect(queue.pending.isEmpty)
        #expect(queue.abandoned.count == 1)
    }

    /// Retrying resets nothing by itself — a success is what clears the count,
    /// or a run of bad luck across launches would exhaust the budget.
    @Test("A success clears the failure count")
    func successResets() {
        var queue = queue()
        queue.enqueue(favourite)
        queue.recordFailure(favourite)
        queue.remove(favourite)

        queue.enqueue(unfavourite)
        for _ in 0..<(ActionQueue.maxAttempts - 1) {
            queue.recordFailure(unfavourite)
        }
        #expect(!queue.pending.isEmpty)
    }

    @Test("Every kind of action round-trips through storage")
    func codable() throws {
        let all: [PendingAction] = [
            .courseFavourite(moodleID: 1, value: true),
            .courseHidden(moodleID: 2, value: false),
            .targetAverage(27.5),
            .favouriteCareer(matricola: "332218"),
        ]
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode([PendingAction].self, from: data) == all)
    }

    @Test("Each kind describes itself for the user")
    func descriptions() {
        #expect(!PendingAction.courseFavourite(moodleID: 1, value: true).label.isEmpty)
        #expect(!PendingAction.targetAverage(27).label.isEmpty)
        #expect(!PendingAction.favouriteCareer(matricola: "1").label.isEmpty)
    }
}

/// Two defects in the first version of the queue.
@Suite("Action queue durability")
struct ActionQueueDurabilityTests {
    private func store() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("dur-\(UUID().uuidString)", isDirectory: true))
    }

    private let favourite = PendingAction.courseFavourite(moodleID: 42, value: true)

    /// The first version kept abandoned actions in memory only. The entry was
    /// removed from the persisted list and the record of its loss was not
    /// written, so a relaunch left the change gone *and* the user never told —
    /// precisely the silent loss the retry budget exists to prevent.
    @Test("An abandoned change survives a relaunch so it can still be reported")
    func abandonedPersists() {
        let store = store()
        var queue = ActionQueue(store: store, account: "1")
        queue.enqueue(favourite)
        for _ in 0..<ActionQueue.maxAttempts { queue.recordFailure(favourite) }
        #expect(queue.abandoned.count == 1)

        let reopened = ActionQueue(store: store, account: "1")
        #expect(reopened.abandoned.count == 1)
        #expect(reopened.pending.isEmpty)
    }

    @Test("Acknowledging a loss is remembered, not repeated at every launch")
    func acknowledgePersists() {
        let store = store()
        var queue = ActionQueue(store: store, account: "1")
        queue.enqueue(favourite)
        for _ in 0..<ActionQueue.maxAttempts { queue.recordFailure(favourite) }
        queue.clearAbandoned()

        #expect(ActionQueue(store: store, account: "1").abandoned.isEmpty)
    }

    /// The second defect: `flush` read a snapshot, and a tap made while it ran
    /// was written by `record` and then overwritten when the flush persisted
    /// its stale copy. The user's change vanished with no failure anywhere.
    @Test("A change made during a flush is not overwritten by it")
    func noLostUpdate() {
        let store = store()
        var flushing = ActionQueue(store: store, account: "1")
        flushing.enqueue(favourite)

        // Another part of the app queues something while the flush holds its
        // snapshot.
        var other = ActionQueue(store: store, account: "1")
        other.enqueue(.targetAverage(28))

        // The flush completes its action and writes back.
        flushing.remove(favourite)

        let reopened = ActionQueue(store: store, account: "1")
        #expect(reopened.pending.contains(.targetAverage(28)))
        #expect(!reopened.pending.contains(favourite))
    }
}
