import Foundation
import OSLog

/// A change the user made that the Politecnico has not been told about yet.
///
/// Four operations in the app write to the university: favouriting a WeBeep
/// course, hiding one, setting a target average, and choosing a favourite
/// career. Without a queue each of them failed silently offline and the UI
/// reverted — the user's tap was simply undone, with no explanation and
/// nothing to retry.
nonisolated enum PendingAction: Codable, Sendable, Equatable {
    case courseFavourite(moodleID: Int, value: Bool)
    case courseHidden(moodleID: Int, value: Bool)
    case targetAverage(Double)
    case favouriteCareer(matricola: String)

    /// What this action is *about*.
    ///
    /// Two actions with the same key are the same change made twice, and only
    /// the last matters: five taps on a star offline should be one request
    /// carrying the value the user settled on, not five requests fighting.
    var targetKey: String {
        switch self {
        case .courseFavourite(let id, _): "course-fav-\(id)"
        case .courseHidden(let id, _): "course-hidden-\(id)"
        case .targetAverage: "target"
        case .favouriteCareer: "career-favourite"
        }
    }

    /// Shown when a change could not be sent, so the user learns which one.
    var label: String {
        switch self {
        case .courseFavourite(_, let value):
            value ? "Corso aggiunto ai preferiti" : "Corso rimosso dai preferiti"
        case .courseHidden(_, let value):
            value ? "Corso nascosto" : "Corso mostrato"
        case .targetAverage(let media):
            "Obiettivo media \(String(format: "%.1f", media))"
        case .favouriteCareer(let matricola):
            "Matricola preferita \(matricola)"
        }
    }
}

/// Changes waiting to reach the Politecnico.
///
/// Ordered, coalesced per target, persisted per account, and bounded: an
/// action the server keeps refusing is abandoned rather than retried on every
/// launch for the rest of the installation's life.
nonisolated struct ActionQueue: Sendable {
    /// How many times to try before giving up. Three is enough to ride out a
    /// bad tunnel and few enough that a genuinely rejected change surfaces
    /// while the user still remembers making it.
    static let maxAttempts = 3

    private struct Entry: Codable, Sendable, Equatable {
        var action: PendingAction
        var failures: Int
    }

    private let store: OfflineStore
    private let account: String?
    private var entries: [Entry] = []
    /// Actions given up on, kept so the UI can say which change was lost
    /// rather than letting it vanish.
    private(set) var abandoned: [PendingAction] = []

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "queue")

    var pending: [PendingAction] { entries.map(\.action) }
    var isEmpty: Bool { entries.isEmpty }

    init(store: OfflineStore = .shared, account: String?) {
        self.store = store
        self.account = account
        entries = store.load([Entry].self, as: "queue", account: account)?.value ?? []
    }

    mutating func enqueue(_ action: PendingAction) {
        if let index = entries.firstIndex(where: { $0.action.targetKey == action.targetKey }) {
            // Replaced in place: a change made first must not jump ahead of
            // one made after it just because it was amended.
            entries[index].action = action
        } else {
            entries.append(Entry(action: action, failures: 0))
        }
        persist()
    }

    mutating func remove(_ action: PendingAction) {
        entries.removeAll { $0.action.targetKey == action.targetKey }
        persist()
    }

    /// Records an attempt that failed, abandoning the action once the budget
    /// is spent.
    mutating func recordFailure(_ action: PendingAction) {
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

    mutating func clearAbandoned() {
        abandoned.removeAll()
    }

    private func persist() {
        store.save(entries, as: "queue", account: account)
    }
}
