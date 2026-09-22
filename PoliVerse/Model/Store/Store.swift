import Foundation
import Observation
import OSLog

/// An observable cache-and-fetch pipeline for a single remote service.
///
/// A store owns one ``Source``. It exposes the last good value, the phase of the
/// current load and the age of what is held, and it drives loading through
/// ``load(force:)``.
///
/// ## Load sequence
///
/// Each call to ``load(force:)`` performs, in order:
///
/// 1. Rejects the call when a load is already in flight, or when the
///    ``LoadWindow`` for this account has not expired and `force` is `false`.
/// 2. Opens a ``PerfSignpost`` interval when ``Source/signpost`` names one.
/// 3. Restores the offline copy for this account, once per account, off the main
///    actor.
/// 4. For a sample account, substitutes ``Source/sample()`` and stops.
/// 5. Fetches through ``Source/fetch(_:)``, writes the result to the offline
///    store when a matricola is known, and marks the window.
///
/// ## Invariants
///
/// - A failed load never clears ``value``. The previously held data stays on
///   screen and ``age`` continues to describe it.
/// - A failed load does not mark the load window, so the next call retries
///   rather than being suppressed for the remainder of the interval.
/// - A cancellation is not a failure: it leaves ``phase`` at ``Phase/idle`` and
///   produces no message.
/// - Every value that reaches ``value`` has passed through
///   ``Source/adjust(_:)``, whatever its origin.
///
/// ## Isolation
///
/// The store is main-actor isolated. Decoding of the offline copy and the
/// network fetch both run off the main actor.
@MainActor
@Observable
final class Store<S: Source> {
    /// The state of the most recent load.
    enum Phase: Equatable {
        /// No load is in flight and the last one, if any, completed or was cancelled.
        case idle
        /// A load is in flight.
        case loading
        /// The last load did not complete. The payload is a message fit to show the
        /// student; ``Store/value`` still holds whatever was there before, which may be
        /// `nil`.
        case failed(String)
    }

    /// The last good value, from the network, the offline copy or the sample set.
    ///
    /// `nil` only before the first successful load on a fresh install, and never
    /// reset to `nil` by a failure.
    private(set) var value: S.Value?
    /// The state of the most recent load.
    private(set) var phase: Phase = .idle
    /// Seconds elapsed since ``value`` was fetched, or `nil` when it did not come
    /// from a dated fetch — sample data, or a signed-out fetch that was not cached.
    private(set) var age: TimeInterval?

    /// The service this store loads.
    private let source: S
    /// Who is signed in, and the transport their requests go through.
    private let account: any Account
    /// Where the offline copy is read from and written to.
    private let offline: OfflineStore
    /// Diagnostic log for this type, under the `store` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "store")
    /// Suppresses loads within ``Source/ttl`` of the last successful one.
    private var window: LoadWindow
    /// The matricola whose offline copy is already in ``value``.
    ///
    /// Guards against a second restore for the same account overwriting a value
    /// that has since been fetched.
    private var restoredFor: String?

    /// Creates a store for one source.
    ///
    /// - Parameters:
    ///   - source: The service to load.
    ///   - account: Supplies the matricola, the sample flag and the transport.
    ///   - offline: Backing store for the offline copy.
    init(_ source: S, account: any Account, offline: OfflineStore = .shared) {
        self.source = source
        self.account = account
        self.offline = offline
        self.window = LoadWindow(interval: S.ttl)
    }

    /// `true` while a load is in flight.
    var isLoading: Bool { phase == .loading }

    /// The message from a ``Phase/failed(_:)`` phase, or `nil` in any other phase.
    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// Identifies the data currently held, so that a change of account — or of the
    /// sample-data toggle — reloads rather than waiting out the load window.
    ///
    /// `"mock"` for a sample account, the matricola when signed in, `"anonymous"`
    /// otherwise.
    private var key: String {
        account.isSample ? "mock" : (account.matricola ?? "anonymous")
    }

    /// Brings ``value`` up to date, subject to the load window.
    ///
    /// Returns without doing anything when a load is already in flight, or when the
    /// window for the current account has not expired and `force` is `false`.
    ///
    /// - Parameter force: Ignores the load window. A load already in flight still
    ///   wins.
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

    /// Applies a local change to the held value without a round trip — a notice
    /// marked read, a favourite toggled.
    ///
    /// The change is not written to the offline copy. ``Source/adjust(_:)`` layers
    /// local state back on along every path, so persisting it here would record the
    /// same fact in two places.
    ///
    /// Does nothing when ``value`` is `nil`.
    ///
    /// - Parameter change: Mutates the held value in place.
    func update(_ change: (inout S.Value) -> Void) {
        guard var current = value else { return }
        change(&current)
        value = current
    }

    /// Reads the offline copy into ``value`` and ``age``, once per account, off the
    /// main actor.
    ///
    /// Skipped for a sample account, when no matricola is known, or when this
    /// account has already been restored.
    private func restoreOfflineCopy() async {
        guard let matricola = account.matricola, !account.isSample,
              matricola != restoredFor else { return }
        restoredFor = matricola
        guard let entry = await Self.read(S.id, account: matricola, from: offline) else { return }
        value = source.adjust(entry.value)
        age = entry.age
    }

    /// Decodes one offline entry on a background executor.
    ///
    /// ``OfflineStore/load(_:as:account:)`` blocks on its write queue and then
    /// decodes synchronously, which a foreground revalidation does for several
    /// services in succession.
    ///
    /// - Parameters:
    ///   - name: The record name, ``Source/id``.
    ///   - account: The matricola the record is keyed by.
    ///   - offline: The store to read from.
    /// - Returns: The decoded entry with its age, or `nil` when there is no usable
    ///   record.
    @concurrent
    private nonisolated static func read(
        _ name: String, account: String, from offline: OfflineStore
    ) async -> OfflineStore.Entry<S.Value>? {
        offline.load(S.Value.self, as: name, account: account)
    }
}
