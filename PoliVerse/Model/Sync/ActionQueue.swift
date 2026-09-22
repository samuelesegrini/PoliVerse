import Foundation
import OSLog

/// A change the student made that the Politecnico has not been told about yet.
///
/// Four operations in the app write to the university, and each has a case here.
/// ``PendingChanges`` applies them locally at once and delivers them later, so
/// one of these is what the app has promised the student and owes the server.
nonisolated enum PendingAction: Codable, Sendable, Equatable {
    /// A WeBeep course starred or unstarred, by its Moodle course id.
    case courseFavourite(moodleID: Int, value: Bool)
    /// A WeBeep course hidden or shown, by its Moodle course id.
    case courseHidden(moodleID: Int, value: Bool)
    /// A new target weighted average for the career.
    case targetAverage(Double)
    /// A career chosen as the favourite, by its matricola.
    case favouriteCareer(matricola: String)

    /// What this action is about, independent of the value it carries.
    ///
    /// ``ActionQueue`` coalesces by this key, so repeated changes to one thing
    /// collapse into a single request carrying the value the student settled on.
    var targetKey: String {
        switch self {
        case .courseFavourite(let id, _): "course-fav-\(id)"
        case .courseHidden(let id, _): "course-hidden-\(id)"
        case .targetAverage: "target"
        case .favouriteCareer: "career-favourite"
        }
    }

    /// A localised description of the change, shown when it could not be sent so that
    /// the student learns which one was lost.
    var label: String {
        switch self {
        case .courseFavourite(_, let value):
            value
                ? String(localized: "Corso aggiunto ai preferiti")
                : String(localized: "Corso rimosso dai preferiti")
        case .courseHidden(_, let value):
            value
                ? String(localized: "Corso nascosto")
                : String(localized: "Corso mostrato")
        case .targetAverage(let media):
            String(localized: "Obiettivo media \(String(format: "%.1f", media))")
        case .favouriteCareer(let matricola):
            String(localized: "Matricola preferita \(matricola)")
        }
    }
}

/// The ordered, persisted set of changes waiting to reach the Politecnico.
///
/// Ordered by when each change was first made, coalesced per
/// ``PendingAction/targetKey``, keyed per account in ``OfflineStore``, and
/// bounded by ``maxAttempts``: an action the server keeps refusing moves to
/// ``abandoned`` rather than being retried for the life of the installation.
///
/// Every mutating method re-reads the file first, so an instance held across an
/// `await` cannot write back a stale snapshot over a change made in the
/// meantime.
nonisolated struct ActionQueue: Sendable {
    /// How many delivery attempts an action gets before it is abandoned.
    static let maxAttempts = 3

    /// One queued action together with how many attempts it has already cost.
    private struct Entry: Codable, Sendable, Equatable {
        /// The change to deliver.
        var action: PendingAction
        /// Failed attempts so far, against ``ActionQueue/maxAttempts``.
        var failures: Int
    }

    /// The persisted file: both what is still waiting and what has been given up on.
    ///
    /// Abandonments are persisted alongside the queue so that a change lost during
    /// one session is still reportable in the next.
    private struct Contents: Codable, Sendable {
        /// Actions still waiting, oldest first.
        var entries: [Entry] = []
        /// Actions whose retry budget is spent.
        var abandoned: [PendingAction] = []
    }

    /// Where the queue file lives.
    private let store: OfflineStore
    /// The matricola the queue is keyed by, or `nil` when signed out.
    private let account: String?
    /// This instance's view of the waiting actions.
    private var entries: [Entry] = []
    /// Actions given up on, kept so that the UI can name the change that was lost
    /// instead of letting it vanish. Cleared by ``clearAbandoned()``.
    private(set) var abandoned: [PendingAction] = []

    /// Diagnostic log for this type, under the `queue` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "queue")

    /// The waiting actions, oldest first, without their attempt counts.
    var pending: [PendingAction] { entries.map(\.action) }
    /// `true` when nothing is waiting. Abandoned actions do not count.
    var isEmpty: Bool { entries.isEmpty }

    /// Reads the queue for one account.
    ///
    /// - Parameters:
    ///   - store: Where the queue file lives.
    ///   - account: The matricola to key the file by, or `nil` when signed out.
    init(store: OfflineStore = .shared, account: String?) {
        self.store = store
        self.account = account
        let contents = store.load(Contents.self, as: "queue", account: account)?.value
        entries = contents?.entries ?? []
        abandoned = contents?.abandoned ?? []
    }

    /// Merges what is on disk into this instance, keeping locally held attempt
    /// counts.
    ///
    /// A flush holds an instance across `await`s, during which the student may make
    /// another change. Any entry on disk this instance has not seen is taken as such
    /// a change and kept.
    private mutating func reload() {
        let contents = store.load(Contents.self, as: "queue", account: account)?.value
        let disk = contents?.entries ?? []
        // Anything on disk this instance has not seen is a change made while
        // it was busy; keep it, and keep our own failure counts.
        for entry in disk where !entries.contains(where: {
            $0.action.targetKey == entry.action.targetKey
        }) {
            entries.append(entry)
        }
        abandoned = contents?.abandoned ?? abandoned
    }

    /// Adds a change, or replaces the waiting change with the same
    /// ``PendingAction/targetKey``.
    ///
    /// A replacement keeps the original position in the queue, so amending a change
    /// does not let it overtake one made after it.
    ///
    /// - Parameter action: The change to deliver.
    mutating func enqueue(_ action: PendingAction) {
        reload()
        if let index = entries.firstIndex(where: { $0.action.targetKey == action.targetKey }) {
            // Replaced in place: a change made first must not jump ahead of
            // one made after it just because it was amended.
            entries[index].action = action
        } else {
            entries.append(Entry(action: action, failures: 0))
        }
        persist()
    }

    /// Drops the waiting change for this action's target, after a successful
    /// delivery.
    ///
    /// - Parameter action: The change that was delivered. Matched by
    ///   ``PendingAction/targetKey``.
    mutating func remove(_ action: PendingAction) {
        reload()
        entries.removeAll { $0.action.targetKey == action.targetKey }
        persist()
    }

    /// Records one failed attempt, moving the action to ``abandoned`` once
    /// ``maxAttempts`` is reached.
    ///
    /// Does nothing when the action is no longer waiting.
    ///
    /// - Parameter action: The change that could not be delivered.
    mutating func recordFailure(_ action: PendingAction) {
        reload()
        guard let index = entries.firstIndex(where: {
            $0.action.targetKey == action.targetKey
        }) else { return }

        entries[index].failures += 1
        if entries[index].failures >= Self.maxAttempts {
            let lost = entries.remove(at: index).action
            abandoned.append(lost)
            log.error("Abandoned after \(Self.maxAttempts, privacy: .public) attempts: \(lost.label, privacy: .public)")
        }
        persist()
    }

    /// Discards the record of abandoned changes and persists the result, so the same
    /// loss is not reported again at the next launch.
    mutating func clearAbandoned() {
        abandoned.removeAll()
        // Persisted, or the same loss is reported again at every launch.
        persist()
    }

    /// Writes both halves of ``Contents`` back to the offline store.
    private func persist() {
        store.save(Contents(entries: entries, abandoned: abandoned),
                   as: "queue", account: account)
    }
}
