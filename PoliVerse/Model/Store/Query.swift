import Foundation
import Observation
import OSLog

/// One key of a ``Resource``, as the screens observe it.
///
/// The main-actor half of the pipeline: it holds what a view reads — the value, the
/// phase, the age — and assigns them, and does nothing else. The fetching, joining,
/// caching and the offline copy belong to the ``Loader`` behind it; the decoding and
/// parsing to the resource's `@concurrent` fetch.
///
/// A view depends on the one query it read, so a change to another key, or to
/// another resource, redraws nothing here. A value is assigned only when it changed,
/// because an `@Observable` property notifies on every assignment.
@MainActor
@Observable
final class Query<R: Resource> {
    /// Where a load is.
    enum Phase: Equatable {
        /// Nothing in flight, and the last load succeeded or none has run.
        case idle
        /// A load is in flight.
        case loading
        /// The last load failed, with the message to show.
        case failed(String)
    }

    /// The current value, after ``Resource/adjust(_:)``: restored, fetched or sample.
    private(set) var value: R.Value?
    /// Where the current load is.
    private(set) var phase: Phase = .idle
    /// Seconds since ``value`` was fetched, as of when it was assigned, or `nil` for
    /// sample data, a signed-out account, or before anything is held.
    private(set) var age: TimeInterval?

    /// The key this query follows.
    let key: R.Key
    private let resource: R
    private let loader: Loader<R>
    private let account: any Account
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "store")
    /// The load in flight, which a second caller joins rather than being turned away.
    @ObservationIgnored private var running: Task<Void, Never>?

    /// Creates a query with a loader of its own.
    ///
    /// - Parameters:
    ///   - resource: What to load.
    ///   - key: Which key.
    ///   - account: Whose data.
    ///   - offline: Where the offline copy lives.
    convenience init(_ resource: R, key: R.Key, account: any Account, offline: OfflineStore = .shared) {
        self.init(resource, key: key, account: account, loader: Loader(resource, offline: offline))
    }

    /// Creates a query sharing a loader with others, so two screens asking for one
    /// key cost one request.
    ///
    /// - Parameters:
    ///   - resource: What to load.
    ///   - key: Which key.
    ///   - account: Whose data.
    ///   - loader: The loader to go through.
    init(_ resource: R, key: R.Key, account: any Account, loader: Loader<R>) {
        self.resource = resource
        self.key = key
        self.account = account
        self.loader = loader
    }

    /// `true` while a load is in flight.
    var isLoading: Bool { phase == .loading }

    /// The last load's error, or `nil` when it succeeded.
    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// Loads the value: the offline copy first, then the network unless a fresh
    /// value is held.
    ///
    /// A call while a load is in flight **joins** it and returns when it finishes,
    /// so pull-to-refresh during the launch refresh ends when the data is in, not at
    /// once. A failure keeps the last good value and says what went wrong; a
    /// cancellation, which is a view going away, says nothing.
    ///
    /// - Parameter force: Fetches even when a fresh value is held.
    func load(force: Bool = false) async {
        if let running {
            await running.value
            return
        }
        let task = Task(name: "\(R.id) load") { await self.run(force: force) }
        running = task
        await task.value
        running = nil
    }

    /// Changes the held value in place, for a change made on the device.
    ///
    /// - Parameter change: The change.
    func update(_ change: @escaping @Sendable (inout R.Value) -> Void) {
        guard var current = value else { return }
        change(&current)
        value = current
        let env = Env(account)
        Task { await loader.update(key, env: env, change) }
    }

    private func run(force: Bool) async {
        let env = Env(account)
        if let restored = await loader.restore(key, env: env) {
            assign(restored, env: env)
        }
        guard await loader.isDue(key, env: env, force: force) else {
            // Another query for the same key may have filled it.
            if let held = await loader.cached(key, env: env) { assign(held, env: env) }
            return
        }
        phase = .loading
        do {
            let snapshot = try await loader.value(key, env: env, force: force)
            assign(snapshot, env: env)
            phase = .idle
        } catch {
            if !PoliMiAPI.isCancellation(error) {
                log.error("\(R.id, privacy: .public) failed: \(error.localizedDescription)")
            }
            // Nil for a cancellation, which is a view going away rather than a
            // failure and must never reach the student.
            phase = userFacingMessage(error).map(Phase.failed) ?? .idle
        }
    }

    private func assign(_ snapshot: Loader<R>.Snapshot, env: Env) {
        let adjusted = resource.adjust(snapshot.value)
        if !Self.same(value, adjusted) { value = adjusted }
        let newAge: TimeInterval? = env.isSample || env.matricola == nil
            ? nil : max(0, Date.now.timeIntervalSince(snapshot.fetchedAt))
        if age != newAge { age = newAge }
    }

    /// Whether two values are equal, when the type can say so.
    private static func same(_ old: R.Value?, _ new: R.Value) -> Bool {
        guard let old, let comparable = old as? any Equatable else { return false }
        return comparable.isEqual(to: new)
    }
}

extension Query where R.Key == Whole {
    /// Creates a query for a resource with one value per account.
    ///
    /// - Parameters:
    ///   - resource: What to load.
    ///   - account: Whose data.
    ///   - offline: Where the offline copy lives.
    convenience init(_ resource: R, account: any Account, offline: OfflineStore = .shared) {
        self.init(resource, key: Whole(), account: account, offline: offline)
    }
}

extension Equatable {
    /// Whether another value is of this type and equal to this one.
    nonisolated func isEqual(to other: Any) -> Bool {
        (other as? Self) == self
    }
}
