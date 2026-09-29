import Foundation
import OSLog

/// Fetches one kind of remote data, and never the same thing twice at once.
///
/// One loader per ``Resource``, not one for the app: a single data actor would queue
/// every screen's loading behind one executor. What it does, for every resource the
/// same way:
///
/// 1. **Joins.** A second caller for a key already being fetched awaits that fetch;
///    eight callers cost one request. Nothing is dropped: a caller that returned
///    early would believe the data had arrived.
/// 2. **Keeps**, for ``Resource/ttl`` on a monotonic clock, up to
///    ``Resource/capacity`` keys, dropping the least recently used. A value held for
///    another account or for sample data is never served.
/// 3. **Warms** keys about to be needed, at `.utility`: below everything on screen,
///    but not starved the way `.background` is under load. A caller who then asks
///    for a key being warmed raises that fetch to its own priority.
/// 4. **Outlives a caller, not all of them.** The work runs in a task the loader
///    holds, so one view going away does not take the fetch from the others waiting.
///    When the last caller waiting is cancelled, the fetch is cancelled too, unless
///    it was a warm-up nobody was waiting for.
/// 5. **Persists** for ``Persistence/offline`` resources: each fetched value is
///    written per account, and ``restore(_:env:)`` puts it back at the next launch
///    before the network answers. A restore that a fetch overtook is dropped.
///
/// The fetch itself runs in the resource's `@concurrent` method, off this actor and
/// off the main actor; this actor only files what comes back.
actor Loader<R: Resource> {
    /// What the loader holds for a key.
    nonisolated struct Snapshot: Sendable {
        /// The value, before ``Resource/adjust(_:)``.
        let value: R.Value
        /// When it was fetched. For a restored value, when the copy on disk was.
        let fetchedAt: Date
        /// `false` for a value restored from disk and not fetched since.
        let isFresh: Bool
    }

    /// One held value.
    private struct Entry {
        var value: R.Value
        var fetchedAt: Date
        /// When it was fetched on the monotonic clock, or `nil` for a restored value,
        /// which is never fresh.
        var stamp: ContinuousClock.Instant?
        var lastUsed: ContinuousClock.Instant
        /// ``Env/source`` of the load that produced it.
        var source: String
    }

    /// One fetch in flight, for one or more keys.
    private struct Flight {
        /// The fetch.
        let task: Task<[R.Key: R.Value], any Error>
        /// The fetch's outcome once filed on this actor. Callers await this rather
        /// than the fetch, so none resumes before the value is held.
        var filed: Task<Result<Void, any Error>, Never>?
        let keys: [R.Key]
        let source: String
        /// Started by ``warm(_:env:)``: nobody waits for it, so nobody leaving
        /// cancels it.
        let warm: Bool
        /// Callers awaiting it and not cancelled.
        var waiters: Int
    }

    private let resource: R
    private let offline: OfflineStore
    private let capacity: Int
    private let clock = ContinuousClock()
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "loader")

    private var entries: [R.Key: Entry] = [:]
    /// The flight each key is part of.
    private var flightOf: [R.Key: Int] = [:]
    private var flights: [Int: Flight] = [:]
    private var nextFlight = 0
    /// `"<matricola>|<file>"` for every offline copy already restored.
    private var restored: Set<String> = []

    /// Creates a loader.
    ///
    /// - Parameters:
    ///   - resource: What to load.
    ///   - offline: Where the offline copy lives.
    ///   - capacity: How many keys to hold; ``Resource/capacity`` by default.
    init(_ resource: R, offline: OfflineStore = .shared, capacity: Int? = nil) {
        self.resource = resource
        self.offline = offline
        self.capacity = capacity ?? R.capacity
    }

    // MARK: - Reading

    /// What is held for a key and account, fresh or not.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - env: Whose data.
    /// - Returns: The snapshot, or `nil` when nothing is held for that account.
    func cached(_ key: R.Key, env: Env) -> Snapshot? {
        guard var entry = entries[key], entry.source == env.source else { return nil }
        entry.lastUsed = clock.now
        entries[key] = entry
        return snapshot(entry)
    }

    /// Whether asking for a key would reach the network: nothing held for this
    /// account, what is held has expired or was only restored, a fetch is already
    /// under way, or `force`.
    func isDue(_ key: R.Key, env: Env, force: Bool = false) -> Bool {
        if force { return true }
        if let id = flightOf[key], flights[id]?.source == env.source { return true }
        guard let entry = entries[key], entry.source == env.source, let stamp = entry.stamp
        else { return true }
        return clock.now - stamp >= .seconds(R.ttl)
    }

    /// Whether a key is held and fresh for this account.
    func isHeld(_ key: R.Key, env: Env) -> Bool {
        guard let entry = entries[key], entry.source == env.source, let stamp = entry.stamp
        else { return false }
        return clock.now - stamp < .seconds(R.ttl)
    }

    // MARK: - Loading

    /// The value for one key: held if fresh, otherwise fetched or joined.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - env: Whose data, through which transport.
    ///   - force: Fetches even when a fresh value is held; pull-to-refresh.
    /// - Returns: The snapshot.
    /// - Throws: The fetch's error. Nothing is cached for a failure.
    func value(_ key: R.Key, env: Env, force: Bool = false) async throws -> Snapshot {
        let values = try await values([key], env: env, force: force)
        guard let value = values[key] else { throw LoaderError.missing(R.id) }
        return value
    }

    /// The values for several keys, fetching what is not held in one call to
    /// ``Resource/fetch(_:env:previous:)-(Array,_,_)`` and joining what is in flight.
    ///
    /// - Parameters:
    ///   - keys: The keys.
    ///   - env: Whose data, through which transport.
    ///   - force: Fetches even the keys held fresh.
    /// - Returns: A snapshot per key that has one.
    /// - Throws: The first error of a fetch this call waited on.
    func values(_ keys: [R.Key], env: Env, force: Bool = false) async throws -> [R.Key: Snapshot] {
        var waitingOn = Set<Int>()
        var toFetch: [R.Key] = []
        for key in keys {
            if let id = flightOf[key], let flight = flights[id], flight.source == env.source {
                // Joined even when forced: a fetch under way is as fresh as a new one.
                waitingOn.insert(id)
            } else if force || isDue(key, env: env) {
                toFetch.append(key)
            }
        }
        if !toFetch.isEmpty {
            waitingOn.insert(start(toFetch, env: env, priority: Task.currentPriority, warm: false))
        }

        var firstError: (any Error)?
        for id in waitingOn {
            do {
                try await join(id)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }

        var result: [R.Key: Snapshot] = [:]
        for key in keys {
            if let snapshot = cached(key, env: env) { result[key] = snapshot }
        }
        return result
    }

    /// Starts fetching keys that are neither held fresh nor in flight, and returns at
    /// once. For what is about to be on screen: never observed, never awaited.
    ///
    /// - Parameters:
    ///   - keys: The keys to warm.
    ///   - env: Whose data.
    func warm(_ keys: some Sequence<R.Key>, env: Env) {
        let due = keys.filter { key in
            flightOf[key].flatMap { flights[$0] }?.source != env.source && isDue(key, env: env)
        }
        guard !due.isEmpty else { return }
        _ = start(due, env: env, priority: .utility, warm: true)
    }

    /// Waits until every fetch in flight has been filed, including warm-ups.
    ///
    /// The background refresh has about thirty seconds and must not report success
    /// before the work has landed.
    func settle() async {
        while let filed = flights.values.first?.filed {
            _ = await filed.value
        }
    }

    // MARK: - Changing what is held

    /// Changes a held value in place, for a change made on the device — a notice
    /// marked read. Not written to disk: the next fetch brings the server's view.
    func update(_ key: R.Key, env: Env, _ change: @Sendable (inout R.Value) -> Void) {
        guard var entry = entries[key], entry.source == env.source else { return }
        change(&entry.value)
        entries[key] = entry
    }

    /// Files a value built elsewhere as if it had just been fetched, and writes its
    /// offline copy — a course's listing, built from a page another loader fetched.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - key: Its key.
    ///   - env: Whose it is.
    func put(_ value: R.Value, for key: R.Key, env: Env) {
        let now = clock.now
        entries[key] = Entry(value: value, fetchedAt: .now, stamp: now, lastUsed: now, source: env.source)
        if R.persistence == .offline, !env.isSample, let matricola = env.matricola {
            resource.save(value, to: offline, as: resource.storageName(for: key), account: matricola)
        }
        evictIfNeeded()
    }

    /// Forgets one key, so the next ask fetches it.
    func invalidate(_ key: R.Key) {
        entries[key] = nil
    }

    /// Forgets everything and cancels every fetch, for sign-out.
    func clear() {
        entries.removeAll()
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
        flightOf.removeAll()
        restored.removeAll()
    }

    /// How many keys are held, for tests.
    var count: Int { entries.count }

    // MARK: - The offline copy

    /// Puts the offline copy of a key back, once per account, before the network
    /// answers.
    ///
    /// The file is read and decoded off this actor. A copy that a fetch overtook while
    /// it was being read is dropped rather than put over newer data.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - env: Whose copy.
    /// - Returns: The restored snapshot, never fresh, or `nil` when there was nothing
    ///   to restore or it was already restored for this account.
    func restore(_ key: R.Key, env: Env) async -> Snapshot? {
        guard R.persistence == .offline, !env.isSample, let matricola = env.matricola else { return nil }
        let name = resource.storageName(for: key)
        guard restored.insert("\(matricola)|\(name)").inserted else { return nil }
        guard let entry = await resource.read(from: offline, as: name, account: matricola) else { return nil }
        // Something newer landed while the file was read.
        if let held = entries[key], held.source == env.source { return nil }
        let restoredEntry = Entry(value: entry.value, fetchedAt: Date.now.addingTimeInterval(-entry.age),
                                  stamp: nil, lastUsed: clock.now, source: env.source)
        entries[key] = restoredEntry
        evictIfNeeded()
        return snapshot(restoredEntry)
    }

    // MARK: - Flights

    /// Starts one fetch for some keys.
    private func start(_ keys: [R.Key], env: Env, priority: TaskPriority, warm: Bool) -> Int {
        nextFlight += 1
        let id = nextFlight
        let resource = resource
        let previous = keys.reduce(into: [R.Key: R.Value]()) { result, key in
            if let entry = entries[key], entry.source == env.source { result[key] = entry.value }
        }
        let task = Task(name: "\(R.id) \(warm ? "warm" : "fetch")", priority: priority) { @concurrent in
            let interval = R.signpost.map(PerfSignpost.begin)
            defer { interval.map(PerfSignpost.end) }
            if env.isSample {
                let samples = keys.compactMap { key in resource.sample(key).map { (key, $0) } }
                if samples.count == keys.count { return Dictionary(uniqueKeysWithValues: samples) }
            }
            return try await resource.fetch(keys, env: env, previous: previous)
        }
        flights[id] = Flight(task: task, keys: keys, source: env.source, warm: warm, waiters: 0)
        for key in keys { flightOf[key] = id }
        // Filed here, on the actor, whoever is or is not waiting.
        flights[id]?.filed = Task(name: "\(R.id) file", priority: priority) { await self.file(id) }
        return id
    }

    /// Awaits a flight on behalf of one caller, raising it to the caller's priority
    /// and cancelling it if this caller was the last one waiting and leaves.
    private func join(_ id: Int) async throws {
        guard var flight = flights[id], let filed = flight.filed else { return }
        flight.waiters += 1
        flights[id] = flight
        // Never lowers: a warm-up someone now waits for runs at their priority.
        flight.task.escalatePriority(to: Task.currentPriority)
        filed.escalatePriority(to: Task.currentPriority)
        let outcome = await withTaskCancellationHandler {
            await filed.value
        } onCancel: {
            Task { await self.leave(id) }
        }
        try outcome.get()
    }

    /// One waiter was cancelled.
    private func leave(_ id: Int) {
        guard var flight = flights[id] else { return }
        flight.waiters -= 1
        flights[id] = flight
        if flight.waiters <= 0, !flight.warm { flight.task.cancel() }
    }

    /// Files what a flight brought, and writes the offline copy.
    ///
    /// - Returns: The flight's outcome, which every caller waiting on it receives.
    private func file(_ id: Int) async -> Result<Void, any Error> {
        guard let task = flights[id]?.task else { return .success(()) }
        let result = await task.result
        guard let flight = flights.removeValue(forKey: id) else { return .success(()) }
        for key in flight.keys where flightOf[key] == id { flightOf[key] = nil }
        let values: [R.Key: R.Value]
        switch result {
        case .success(let fetched):
            values = fetched
        case .failure(let error):
            if !PoliMiAPI.isCancellation(error) {
                // Debug: the query reporting it to the screen logs it as an error, and
                // a room whose timetable is hidden is not one.
                log.debug("\(R.id, privacy: .public) failed: \(error.localizedDescription)")
            }
            return .failure(error)
        }
        let now = clock.now
        let date = Date.now
        for (key, value) in values {
            entries[key] = Entry(value: value, fetchedAt: date, stamp: now, lastUsed: now, source: flight.source)
            if R.persistence == .offline, flight.source != "mock", flight.source != "anonymous" {
                resource.save(value, to: offline, as: resource.storageName(for: key), account: flight.source)
            }
        }
        evictIfNeeded()
        return .success(())
    }

    private func snapshot(_ entry: Entry) -> Snapshot {
        Snapshot(value: entry.value, fetchedAt: entry.fetchedAt, isFresh: entry.stamp != nil)
    }

    private func evictIfNeeded() {
        guard entries.count > capacity else { return }
        let ordered = entries.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (key, _) in ordered.prefix(entries.count - capacity) where flightOf[key] == nil {
            entries[key] = nil
        }
    }
}

/// A failure the loader itself reports.
nonisolated enum LoaderError: LocalizedError {
    /// A fetch returned without a value for a key it was asked for.
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let id): "\(id): la risposta non conteneva il dato richiesto."
        }
    }
}
