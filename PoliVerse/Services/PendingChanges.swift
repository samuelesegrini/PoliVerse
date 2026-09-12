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

    private let session: Session
    private let network: NetworkMonitor
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "queue")

    /// Set by the app once WeBeep exists — the queue is built before it, and
    /// two of the four actions are WeBeep's.
    var weBeep: WeBeepService?
    var careers: CareersService?
    var career: CareerService?
    var courses: CourseService?

    init(session: Session, network: NetworkMonitor) {
        self.session = session
        self.network = network
        refresh()
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
        ActionQueue(account: session.student?.matricola)
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
        guard !isFlushing, network.isOnline, session.student != nil else { return }
        var queue = queue()
        guard !queue.isEmpty else { return }

        isFlushing = true
        defer { isFlushing = false }

        for action in queue.pending {
            let sent = await send(action)
            if sent {
                queue.remove(action)
                // The override exists only while the change is unsent.
                courses?.confirmDelivered(action)
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

    func acknowledgeFailures() {
        var queue = queue()
        queue.clearAbandoned()
        failed = []
        count = queue.pending.count
    }

    private func send(_ action: PendingAction) async -> Bool {
        switch action {
        case .courseFavourite(let moodleID, let value):
            guard let weBeep else { return false }
            return await weBeep.setFavourite(value, moodleID: moodleID)
        case .courseHidden(let moodleID, let value):
            guard let weBeep else { return false }
            return await weBeep.setHidden(value, moodleID: moodleID)
        case .targetAverage(let media):
            guard let career else { return false }
            return await career.saveTarget(media)
        case .favouriteCareer(let matricola):
            guard let careers,
                  let match = careers.careers.first(where: { $0.matricola == matricola })
            else { return false }
            await careers.markFavourite(match)
            return true
        }
    }
}
