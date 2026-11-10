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
    /// When each part of ``value`` was fetched. A part missing here has never
    /// answered: what ``value`` holds for it is a default, not data.
    private(set) var parts: [R.Part: Date] = [:]
    /// The parts that answered since the app started, rather than being restored.
    private(set) var arrived: Set<R.Part> = []
    /// The parts whose last request failed.
    private(set) var failed: Set<R.Part> = []
    /// The parts the load in flight asked for that have not answered yet.
    private(set) var pending: Set<R.Part> = []

    /// The key this query follows.
    let key: R.Key
    private let resource: R
    private let loader: Loader<R>
    private let account: any Account
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "store")
    /// The load in flight, which a second caller joins rather than being turned away.
    @ObservationIgnored private var running: Task<Void, Never>?
    /// When the load in flight reached for the network.
    @ObservationIgnored private var asked: ContinuousClock.Instant?
    /// The least time between two values shown while a fetch is handing over
    /// its parts: a burst of answers costs one redraw, not one each.
    private static var coalescing: Duration { .milliseconds(100) }

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

    /// `true` while a load is in flight and nothing is held yet.
    ///
    /// Every screen reads it as "loading and empty", so a refresh over a held value
    /// does not report it: flipping it on and off around a load that a cache or a
    /// joined flight answers within the frame redrew every screen reading it twice
    /// in that frame, and the Liquid Glass surfaces on them warned "glassEffect()
    /// tried to update multiple times per frame".
    var isLoading: Bool { phase == .loading }

    /// The last load's error, or `nil` when it succeeded.
    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// Whether every one of some parts is in ``value``, restored or fetched.
    ///
    /// A figure computed from several parts is shown only when this is `true` for
    /// all of them: an average over half the marks is a wrong number, not an
    /// early one.
    ///
    /// - Parameter needed: The parts the figure is computed from.
    func has(_ needed: R.Part...) -> Bool {
        needed.allSatisfy { parts[$0] != nil }
    }

    /// The state of the section that shows one part.
    ///
    /// - Parameters:
    ///   - part: The part the section shows.
    ///   - isEmpty: Whether what ``value`` holds for it is empty.
    /// - Returns: ``LoadPhase/empty`` only when the part answered with nothing and
    ///   is not being asked again; while it is on its way, ``LoadPhase/waiting(since:)``.
    func phase(of part: R.Part, isEmpty: Bool) -> LoadPhase {
        let waited = asked.map { ContinuousClock.now - $0 } ?? .zero
        if let date = parts[part] {
            if !isEmpty {
                return arrived.contains(part) ? .arrived : .held(age: max(0, Date.now.timeIntervalSince(date)))
            }
            return pending.contains(part) ? .waiting(since: waited) : .empty
        }
        if pending.contains(part) || phase == .loading { return .waiting(since: waited) }
        if let message = errorMessage { return .failed(message) }
        if failed.contains(part) { return .failed(String(localized: "Il servizio non ha risposto.")) }
        return .waiting(since: .zero)
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
        if value == nil { setPhase(.loading) }
        asked = .now
        setPending(await loader.dueParts(key, env: env, force: force))
        // What the fetch has so far is shown as each part is filed.
        let filed = await loader.updates(key, env: env)
        let watching = Task(name: "\(R.id) parts") { [weak self] in
            for await snapshot in filed {
                guard let self, !Task.isCancelled else { return }
                self.assign(snapshot, env: env)
                self.setPending(self.pending.subtracting(snapshot.arrived).subtracting(snapshot.failed))
                try? await Task.sleep(for: Query.coalescing)
            }
        }
        defer {
            asked = nil
            setPending([])
        }
        do {
            let snapshot = try await loader.value(key, env: env, force: force)
            watching.cancel()
            assign(snapshot, env: env)
            setPhase(.idle)
        } catch {
            watching.cancel()
            // The parts that did answer stay: a failure never takes content away.
            if let held = await loader.cached(key, env: env) { assign(held, env: env) }
            if !PoliMiAPI.isCancellation(error) {
                log.error("\(R.id, privacy: .public) failed: \(error.localizedDescription)")
            }
            // Nil for a cancellation, which is a view going away rather than a
            // failure and must never reach the student.
            setPhase(userFacingMessage(error).map(Phase.failed) ?? .idle)
        }
    }

    /// Assigns the phase only when it changes, for the same reason as ``assign(_:env:)``.
    private func setPhase(_ new: Phase) {
        if phase != new { phase = new }
    }

    private func assign(_ snapshot: Loader<R>.Snapshot, env: Env) {
        let adjusted = resource.adjust(snapshot.value)
        if !Self.same(value, adjusted) { value = adjusted }
        let newAge: TimeInterval? = env.isSample || env.matricola == nil
            ? nil : max(0, Date.now.timeIntervalSince(snapshot.fetchedAt))
        if age != newAge { age = newAge }
        if parts != snapshot.parts { parts = snapshot.parts }
        if arrived != snapshot.arrived { arrived = snapshot.arrived }
        if failed != snapshot.failed { failed = snapshot.failed }
    }

    private func setPending(_ new: Set<R.Part>) {
        if pending != new { pending = new }
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
