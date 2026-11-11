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
/// 6. **Keeps parts apart.** For a resource that declares a ``Resource/Part``, each
///    part has its own age: a refresh asks only for the parts that are old, a part
///    that answers is held and written at once, whatever happens to the others, and
///    ``updates(_:env:)`` tells whoever is watching.
/// 7. **Notices changes.** When a part answers over a copy already held, the
///    resource is asked what changed, by the identity of the items, and the answer
///    travels with the snapshot.
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
        /// When each part in ``value`` was fetched. A part missing here has never
        /// answered for this account: what ``value`` shows for it is a default.
        let parts: [R.Part: Date]
        /// The parts that answered since the app started, rather than being restored.
        let arrived: Set<R.Part>
        /// The parts whose last request failed.
        let failed: Set<R.Part>
        /// What the last answer of each part changed with respect to the copy
        /// held before it. A part that answered over nothing is not here.
        let changes: [R.Part: ChangeSet]
    }

    /// What a fetch brings for one key.
    private typealias Fetched = LoadProgress<R>.Snapshot

    /// When one part was fetched.
    private struct PartStamp {
        /// On the calendar, for showing its age and for the offline copy.
        var date: Date
        /// On the monotonic clock, or `nil` for a restored part too old to count
        /// as fresh.
        var instant: ContinuousClock.Instant?
    }

    /// One held value.
    private struct Entry {
        var value: R.Value
        var fetchedAt: Date
        /// When each part was fetched. A resource without parts has one, ``Whole``.
        var parts: [R.Part: PartStamp] = [:]
        /// The parts a fetch answered since the app started.
        var arrived: Set<R.Part> = []
        /// The parts whose last request failed, and when.
        var failed: [R.Part: ContinuousClock.Instant] = [:]
        /// What the last answer of each part changed in the copy held before it.
        var changes: [R.Part: ChangeSet] = [:]
        var lastUsed: ContinuousClock.Instant
        /// ``Env/source`` of the load that produced it.
        var source: String
        /// Fetched by a warm-up and not served to anyone yet. The ledger counts
        /// how many of these are ever used.
        var unusedWarmUp = false
    }

    /// One fetch in flight, for one or more keys.
    private struct Flight {
        /// The fetch.
        let task: Task<[R.Key: Fetched], any Error>
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
        /// Someone asked for a key of this warm-up while it was in flight.
        var claimed = false
        /// The parts already filed while the fetch was still running.
        var stamped: [R.Key: Set<R.Part>] = [:]
    }

    /// Every part there is.
    private static var allParts: Set<R.Part> { Set(R.Part.allCases) }
    /// Whether the resource declares parts of its own.
    private static var hasParts: Bool { R.Part.self != Whole.self }

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
    /// Who is watching each key, and for which account.
    private var watchers: [R.Key: [UUID: (source: String, continuation: AsyncStream<Snapshot>.Continuation)]] = [:]

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
        if entry.unusedWarmUp, isHeld(key, env: env) {
            // Served fresh because a warm-up fetched it: the warm-up paid off.
            entry.unusedWarmUp = false
            LoadingLedger.shared.noteSpeculation(part: R.id, used: 1)
        }
        entries[key] = entry
        return snapshot(entry)
    }

    /// Whether asking for a key would reach the network: nothing held for this
    /// account, what is held has expired or was only restored, a fetch is already
    /// under way, or `force`.
    func isDue(_ key: R.Key, env: Env, force: Bool = false) -> Bool {
        if force { return true }
        if let id = flightOf[key], flights[id]?.source == env.source { return true }
        return !dueParts(key, env: env).isEmpty
    }

    /// Whether a key is held and every part of it is fresh for this account.
    func isHeld(_ key: R.Key, env: Env) -> Bool {
        guard let entry = entries[key], entry.source == env.source else { return false }
        return expiredParts(of: entry).isEmpty
    }

    /// The parts a load of this key would ask for: those never fetched for this
    /// account or older than ``Resource/maxAge(of:)``, leaving out a part that
    /// failed less than ``Resource/retryAfter`` ago. Every part when `force`.
    func dueParts(_ key: R.Key, env: Env, force: Bool = false) -> Set<R.Part> {
        if force { return Self.allParts }
        guard let entry = entries[key], entry.source == env.source else { return Self.allParts }
        let now = clock.now
        return expiredParts(of: entry).filter { part in
            guard let failedAt = entry.failed[part] else { return true }
            return now - failedAt >= .seconds(R.retryAfter)
        }
    }

    /// The parts of an entry that are missing or past their age.
    private func expiredParts(of entry: Entry) -> Set<R.Part> {
        let now = clock.now
        return Self.allParts.filter { part in
            guard let instant = entry.parts[part]?.instant else { return true }
            let maxAge = R.maxAge(of: part)
            return maxAge.isFinite && now - instant >= .seconds(maxAge)
        }
    }

    /// What is filed for a key from now on, newest only: every part that answers
    /// while a fetch runs, and the fetch's end. For a ``Query`` to show a section as
    /// soon as its part is in. Ends when the caller stops reading.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - env: Whose data; another account's is never delivered.
    func updates(_ key: R.Key, env: Env) -> AsyncStream<Snapshot> {
        let (stream, continuation) = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        watchers[key, default: [:]][id] = (env.source, continuation)
        continuation.onTermination = { _ in Task { await self.unwatch(key, id) } }
        return stream
    }

    private func unwatch(_ key: R.Key, _ id: UUID) {
        watchers[key]?[id] = nil
        if watchers[key]?.isEmpty == true { watchers[key] = nil }
    }

    private func notify(_ key: R.Key, _ entry: Entry) {
        guard let watching = watchers[key] else { return }
        let snapshot = snapshot(entry)
        for watcher in watching.values where watcher.source == entry.source {
            watcher.continuation.yield(snapshot)
        }
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
                if flight.warm { flights[id]?.claimed = true }
            } else if force || isDue(key, env: env) {
                toFetch.append(key)
            }
        }
        if !toFetch.isEmpty {
            waitingOn.insert(start(toFetch, env: env, priority: Task.currentPriority, warm: false, force: force))
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
        _ = start(due, env: env, priority: .utility, warm: true, force: false)
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
        let date = Date.now
        var entry = Entry(value: value, fetchedAt: date, lastUsed: now, source: env.source)
        for part in Self.allParts { entry.parts[part] = PartStamp(date: date, instant: now) }
        entry.arrived = Self.allParts
        entries[key] = entry
        persist(key, entry)
        notify(key, entry)
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
    /// A copy younger than ``Resource/ttl`` counts as fresh, aged from when it was
    /// fetched: a launch a few minutes after the last one — or after a background
    /// refresh — serves it without asking, as a return from the app switcher serves
    /// what is in memory. An older copy is shown and fetched again.
    ///
    /// - Parameters:
    ///   - key: The key.
    ///   - env: Whose copy.
    /// - Returns: The restored snapshot, or `nil` when there was nothing to restore or
    ///   it was already restored for this account.
    func restore(_ key: R.Key, env: Env) async -> Snapshot? {
        guard R.persistence != .memory, !env.isSample, let matricola = persistenceAccount(env) else { return nil }
        let name = resource.storageName(for: key)
        guard restored.insert("\(matricola)|\(name)").inserted else { return nil }
        guard let saved = await resource.read(from: offline, as: name, account: matricola) else { return nil }
        // Which parts the copy really holds, and how old each is. A copy written
        // before parts were kept apart has no such list: every part is as old as
        // the file.
        var dates: [String: Date]?
        if Self.hasParts, R.persistence == .offline {
            dates = await offline.loaded([String: Date].self, as: name + Self.partsSuffix, account: matricola)?.value
        }
        // Something newer landed while the file was read.
        if let held = entries[key], held.source == env.source { return nil }
        let now = clock.now
        let today = Date.now
        var restoredEntry = Entry(value: saved.value, fetchedAt: today.addingTimeInterval(-saved.age),
                                  lastUsed: now, source: env.source)
        for part in Self.allParts {
            var age = saved.age
            if let dates {
                // A part the copy never received stays missing, so it is asked for.
                guard let date = dates[String(describing: part)] else { continue }
                age = today.timeIntervalSince(date)
            }
            // A negative age is a clock set back since the save: nothing to trust.
            let fresh = age >= 0 && age < R.maxAge(of: part)
            restoredEntry.parts[part] = PartStamp(date: today.addingTimeInterval(-age),
                                                  instant: fresh ? now.advanced(by: .seconds(-age)) : nil)
        }
        entries[key] = restoredEntry
        evictIfNeeded()
        return snapshot(restoredEntry)
    }

    // MARK: - Flights

    /// Starts one fetch for some keys.
    private func start(_ keys: [R.Key], env: Env, priority: TaskPriority, warm: Bool, force: Bool) -> Int {
        nextFlight += 1
        let id = nextFlight
        let resource = resource
        let previous = keys.reduce(into: [R.Key: R.Value]()) { result, key in
            if let entry = entries[key], entry.source == env.source { result[key] = entry.value }
        }
        let all = Self.allParts
        let hasParts = Self.hasParts
        // Only the parts that are old, so a refresh costs what changed.
        let wanted = keys.reduce(into: [R.Key: Set<R.Part>]()) { result, key in
            let due = dueParts(key, env: env, force: force)
            result[key] = due.isEmpty ? all : due
        }
        let task = Task(name: "\(R.id) \(warm ? "warm" : "fetch")", priority: priority) {
            @concurrent () async throws -> [R.Key: Fetched] in
            let interval = R.signpost.map(PerfSignpost.begin)
            defer { interval.map(PerfSignpost.end) }
            if env.isSample {
                let samples = keys.compactMap { key in
                    resource.sample(key).map { (key, Fetched(value: $0, arrived: all, failed: [])) }
                }
                if samples.count == keys.count { return Dictionary(uniqueKeysWithValues: samples) }
            }
            // What the requests of this fetch are for, read by ``RequestGate``.
            return try await LoadContext.$current.withValue(.init(part: R.id, speculative: warm)) {
                guard hasParts else {
                    return try await resource.fetch(keys, env: env, previous: previous)
                        .mapValues { Fetched(value: $0, arrived: all, failed: []) }
                }
                return try await withThrowingTaskGroup(of: (R.Key, Fetched).self) { group in
                    for key in keys {
                        let parts = wanted[key] ?? all
                        let held = previous[key]
                        group.addTask(name: "\(R.id) \(key)") {
                            // Each part is filed as it answers, while the rest are
                            // still on their way.
                            let progress = LoadProgress<R>()
                            let filing = Task {
                                for await snapshot in progress.snapshots {
                                    await self.filePartial(id, key: key, snapshot)
                                }
                            }
                            do {
                                let fetched = try await resource.fetch(key, env: env, parts: parts,
                                                                       over: held, progress: progress)
                                progress.finish()
                                await filing.value
                                return (key, fetched)
                            } catch {
                                progress.finish()
                                await filing.value
                                throw error
                            }
                        }
                    }
                    var fetched: [R.Key: Fetched] = [:]
                    for try await (key, value) in group { fetched[key] = value }
                    return fetched
                }
            }
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
        let values: [R.Key: Fetched]
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
        if flight.warm {
            LoadingLedger.shared.noteSpeculation(
                part: R.id, sent: values.count, used: flight.claimed ? values.count : 0)
        }
        for (key, fetched) in values {
            let held = entries[key].flatMap { $0.source == flight.source ? $0 : nil }
            var entry = held ?? Entry(value: fetched.value, fetchedAt: date, lastUsed: now, source: flight.source)
            entry.value = fetched.value
            entry.fetchedAt = date
            entry.lastUsed = now
            entry.unusedWarmUp = flight.warm && !flight.claimed
            stamp(&entry, with: fetched, over: held?.value, alreadyStamped: flight.stamped[key] ?? [],
                  now: now, date: date)
            entries[key] = entry
            persist(key, entry)
            notify(key, entry)
        }
        evictIfNeeded()
        return .success(())
    }

    /// Files what a fetch still running has so far: the parts that answered are
    /// held, written and announced now, so they survive whatever happens next.
    private func filePartial(_ id: Int, key: R.Key, _ fetched: Fetched) {
        guard var flight = flights[id] else { return }
        let now = clock.now
        let date = Date.now
        let held = entries[key].flatMap { $0.source == flight.source ? $0 : nil }
        var entry = held ?? Entry(value: fetched.value, fetchedAt: date, lastUsed: now, source: flight.source)
        entry.value = fetched.value
        stamp(&entry, with: fetched, over: held?.value, alreadyStamped: flight.stamped[key] ?? [],
              now: now, date: date)
        flight.stamped[key, default: []].formUnion(fetched.arrived)
        flights[id] = flight
        entries[key] = entry
        persist(key, entry)
        notify(key, entry)
    }

    /// Dates the parts a fetch answered, notes what each changed in the copy
    /// held before it, and notes the parts that failed.
    ///
    /// - Parameter before: The value held before this answer, or `nil` when
    ///   nothing was: an answer over nothing is a first look, not a change.
    private func stamp(_ entry: inout Entry, with fetched: Fetched, over before: R.Value?,
                       alreadyStamped: Set<R.Part>, now: ContinuousClock.Instant, date: Date) {
        for part in fetched.arrived {
            if !alreadyStamped.contains(part) {
                // Compared only with a copy of this very part: what the value
                // shows for a part that never answered is a default.
                if let before, entry.parts[part] != nil {
                    entry.changes[part] = resource.changes(in: part, from: before, to: fetched.value)
                } else {
                    entry.changes[part] = nil
                }
                entry.parts[part] = PartStamp(date: date, instant: now)
            }
            entry.failed[part] = nil
        }
        entry.arrived.formUnion(fetched.arrived)
        for part in fetched.failed.subtracting(fetched.arrived) { entry.failed[part] = now }
    }

    /// The suffix of the file that says when each part of a copy was fetched.
    private static var partsSuffix: String { ".parts" }

    /// Writes an entry's offline copy and, for a resource with parts, when each
    /// part was fetched. The value first: cut between the two, the newest part is
    /// asked for again rather than believed fresher than it is.
    private func persist(_ key: R.Key, _ entry: Entry) {
        guard R.persistence != .memory, entry.source != "mock",
              R.persistence == .publicDisk || entry.source != "anonymous" else { return }
        let name = resource.storageName(for: key)
        resource.save(entry.value, to: offline, as: name, account: entry.source)
        if Self.hasParts, R.persistence == .offline, R.Value.self is any Encodable.Type {
            let dates = Dictionary(uniqueKeysWithValues: entry.parts.map { (String(describing: $0.key), $0.value.date) })
            offline.save(dates, as: name + Self.partsSuffix, account: entry.source)
        }
    }

    private func persistenceAccount(_ env: Env) -> String? {
        R.persistence == .publicDisk ? "public" : env.matricola
    }

    private func snapshot(_ entry: Entry) -> Snapshot {
        Snapshot(value: entry.value, fetchedAt: entry.fetchedAt,
                 isFresh: Self.allParts.allSatisfy { entry.parts[$0]?.instant != nil },
                 parts: entry.parts.mapValues(\.date), arrived: entry.arrived, failed: Set(entry.failed.keys),
                 changes: entry.changes)
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
