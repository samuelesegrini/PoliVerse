import Foundation
import Observation
import OSLog

/// One service's data, and the one pipeline that keeps it current.
///
/// ## What this replaces
///
/// Every service in the app wrote the same seven steps by hand: guard on
/// ``LoadWindow``, open a signpost, restore the offline copy, branch on sample
/// data, fetch, turn the error into a sentence, then save and stamp the age.
/// Nineteen copies, and they had drifted — ``CareerModel`` keeps the last good
/// data when a load fails, `RoomsModel` did not; `CareerModel` decoded its
/// offline copy on the main actor, `RoomsModel` deliberately did not. Those are
/// policy decisions, and policy decided nineteen times is policy decided
/// nowhere.
///
/// The interface is four things to read and two to call. Everything above is
/// behind it.
///
/// ## What it deliberately does not do
///
/// A failed load **never** clears ``value``. What is held is real data that was
/// the student's; it stays, and ``age`` says how old it is. A failed load also
/// does not mark the window, so the next appearance retries rather than
/// serving an error for the whole interval.
@MainActor
@Observable
final class Store<S: Source> {
    /// Where the load is, as the UI needs to know it.
    enum Phase: Equatable {
        case idle
        case loading
        /// The last load did not get what it went for. ``value`` is whatever
        /// was held before, which may be nil.
        case failed(String)
    }

    /// The last good value, from the network, the offline copy or the sample
    /// set. Nil only before the first load of a fresh install.
    private(set) var value: S.Value?
    private(set) var phase: Phase = .idle
    /// Seconds since ``value`` was fetched, or nil if it never was.
    private(set) var age: TimeInterval?

    private let source: S
    private let account: any Account
    private let offline: OfflineStore
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "store")
    private var window: LoadWindow
    /// The account whose offline copy is already in ``value``. Restoring twice
    /// for one account would overwrite a fresh fetch with what is on disk.
    private var restoredFor: String?

    init(_ source: S, account: any Account, offline: OfflineStore = .shared) {
        self.source = source
        self.account = account
        self.offline = offline
        self.window = LoadWindow(interval: S.ttl)
    }

    var isLoading: Bool { phase == .loading }

    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// Identifies the data currently held, so a change of account — or of the
    /// sample-data toggle — reloads instead of waiting out the window.
    private var key: String {
        account.isSample ? "mock" : (account.matricola ?? "anonymous")
    }

    func load(force: Bool = false) async {
        guard phase != .loading, window.shouldLoad(force: force, source: key) else { return }
        phase = .loading
        // After the guard, so a skipped call is not timed as a fast one.
        let interval = S.signpost.map(PerfSignpost.begin)
        defer { interval.map(PerfSignpost.end) }

        await restoreOfflineCopy()

        if account.isSample {
            value = source.adjust(source.sample())
            age = nil
            window.markLoaded(source: key)
            phase = .idle
            return
        }

        let env = Env(http: account.http, matricola: account.matricola, isSample: false)
        do {
            let fetched = try await source.fetch(env)
            value = source.adjust(fetched)
            window.markLoaded(source: key)
            if let matricola = account.matricola {
                offline.save(fetched, as: S.id, account: matricola)
                age = 0
            } else {
                // Signed out, so nothing was cached — and an age carried over
                // from the previous account would describe data that is no
                // longer on screen.
                age = nil
            }
            phase = .idle
        } catch {
            log.error("\(S.id, privacy: .public) failed: \(error.localizedDescription)")
            // Nil for a cancellation, which is a view going away rather than a
            // failure and must never reach the student.
            phase = userFacingMessage(error).map(Phase.failed) ?? .idle
        }
    }

    /// Applies a local change to the held value — a notice marked read, a
    /// favourite toggled — without a round trip.
    ///
    /// The change is not written to the offline copy: it is layered back on by
    /// ``Source/adjust(_:)`` on every path, so persisting it here would record
    /// the same fact twice and let the two disagree.
    func update(_ change: (inout S.Value) -> Void) {
        guard var current = value else { return }
        change(&current)
        value = current
    }

    /// Reads the offline copy once per account, off the main actor.
    ///
    /// Decoding happens on a background executor because ``OfflineStore/load``
    /// blocks on the write queue and then decodes synchronously, and this runs
    /// during a foreground revalidation that does it for five services in a
    /// row. Only ``RoomsModel`` got this right by hand; here every service does.
    private func restoreOfflineCopy() async {
        guard let matricola = account.matricola, !account.isSample,
              matricola != restoredFor else { return }
        restoredFor = matricola
        guard let entry = await Self.read(S.id, account: matricola, from: offline) else { return }
        value = source.adjust(entry.value)
        age = entry.age
    }

    @concurrent
    private nonisolated static func read(
        _ name: String, account: String, from offline: OfflineStore
    ) async -> OfflineStore.Entry<S.Value>? {
        offline.load(S.Value.self, as: name, account: account)
    }
}
