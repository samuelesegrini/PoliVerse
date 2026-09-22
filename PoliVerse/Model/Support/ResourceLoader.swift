import Foundation
import OSLog

/// A keyed cache that fetches once, shares the result among concurrent callers,
/// expires by time, bounds itself by capacity and can be warmed ahead of use.
///
/// ## Coalescing
///
/// ``value(for:)`` joins a fetch already running for the same key, so several
/// screens asking for one resource at once cost one request and all receive the
/// answer.
///
/// ## Prefetching
///
/// ``prefetch(_:)-(Key)`` queues a fetch at background priority and returns
/// immediately, so the next thing can be warmed while the student reads this one.
/// ``settle()`` waits for everything queued, which tests and the background
/// refresh both need.
///
/// ## Isolation and cancellation
///
/// An actor, so the cache and the in-flight table stay consistent without a lock
/// and fetches do not serialise behind the main actor. Fetches run in unstructured
/// `Task`s held by the actor and callers await their value, so a caller that goes
/// away does not cancel a fetch other callers are still waiting on.
///
/// Failures are never cached: one flaky moment must not poison a key for the life
/// of the process.
actor ResourceLoader<Key: Hashable & Sendable, Value: Sendable> {
    /// Produces the value for a key. Returning `nil` means the fetch failed, and
    /// failures are not cached.
    typealias Fetch = @Sendable (Key) async -> Value?

    /// A cached value with the times that govern expiry and eviction.
    private struct Entry {
        /// The cached value.
        let value: Value
        /// When the value was filed, which ``lifetime`` is measured from.
        let storedAt: ContinuousClock.Instant
        /// When the value was last read, which eviction orders by.
        var lastUsed: ContinuousClock.Instant
    }

    /// How a missing value is produced.
    private let fetch: Fetch
    /// How long a cached value stays good.
    private let lifetime: Duration
    /// How many values to hold before evicting.
    private let capacity: Int
    /// The clock expiry and eviction are measured against.
    private let clock = ContinuousClock()
    /// Diagnostic log for this type, under the `loader` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "loader")

    /// The cached values.
    private var cache: [Key: Entry] = [:]
    /// Fetches currently running, by key.
    private var inFlight: [Key: Task<Value?, Never>] = [:]
    /// The task that files each result once its fetch returns.
    ///
    /// Tracked separately from ``inFlight`` because awaiting a fetch is not the same as
    /// the cache having been written; ``settle()`` waits on these.
    private var filing: [Key: Task<Void, Never>] = [:]

    /// Creates a loader.
    ///
    /// - Parameters:
    ///   - lifetime: How long a value stays good.
    ///   - capacity: How many values to hold before the least recently used are
    ///     evicted.
    ///   - fetch: Produces the value for a key.
    init(
        lifetime: Duration = .seconds(300),
        capacity: Int = 128,
        fetch: @escaping Fetch
    ) {
        self.lifetime = lifetime
        self.capacity = capacity
        self.fetch = fetch
    }

    /// How many values are cached, expired ones included.
    var count: Int { cache.count }

    /// Whether a key has an unexpired value.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` when a value is cached and within ``lifetime``.
    func isCached(_ key: Key) -> Bool {
        guard let entry = cache[key] else { return false }
        return clock.now - entry.storedAt < lifetime
    }

    /// The value for a key, fetching it if needed and joining any fetch already
    /// running.
    ///
    /// A cache hit refreshes the key's eviction position.
    ///
    /// - Parameter key: What to load.
    /// - Returns: The value, or `nil` when the fetch failed.
    func value(for key: Key) async -> Value? {
        if let entry = cache[key], clock.now - entry.storedAt < lifetime {
            cache[key]?.lastUsed = clock.now
            return entry.value
        }

        // Someone is already on it. Awaiting their task rather than starting
        // our own is what makes eight simultaneous callers cost one request.
        if let running = inFlight[key] {
            return await running.value
        }

        return await start(key).value
    }

    /// Queues a fetch for a key and returns immediately.
    ///
    /// Runs at background priority, so it yields to anything the student is waiting on.
    /// Does nothing when the key is already cached or already in flight.
    ///
    /// - Parameter key: What to warm.
    func prefetch(_ key: Key) {
        guard !isCached(key), inFlight[key] == nil else { return }
        _ = start(key, priority: .background)
    }

    /// Queues a fetch for each key and returns immediately.
    ///
    /// - Parameter keys: What to warm.
    func prefetch(_ keys: some Sequence<Key>) {
        for key in keys { prefetch(key) }
    }

    /// Waits until every queued fetch has been filed.
    ///
    /// Prefetches run at background priority, which the system may starve for a long
    /// time — acceptable in the app, unusable in a test or in a background refresh that
    /// must not report completion early. Loops, because a fetch may queue more while it
    /// is awaited.
    func settle() async {
        // Loops because a caller may queue more while we wait; terminates
        // because each pass awaits tasks that clear their own entry.
        while !filing.isEmpty {
            for task in Array(filing.values) { await task.value }
        }
    }

    /// Drops the cached value for a key, leaving any fetch in flight alone.
    ///
    /// - Parameter key: What to forget.
    func invalidate(_ key: Key) {
        cache[key] = nil
    }

    /// Empties the cache and cancels everything in flight.
    ///
    /// Used on sign-out, so the next person on the device does not inherit the last
    /// one's data.
    func clear() {
        cache.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        for task in filing.values { task.cancel() }
        filing.removeAll()
    }

    /// Starts a fetch and the task that files its result.
    ///
    /// Filing happens in a second task because recording the result must run on the
    /// actor, which the fetch task cannot do without re-entering it.
    ///
    /// - Parameters:
    ///   - key: What to load.
    ///   - priority: The fetch task's priority.
    /// - Returns: The fetch task, which callers may await.
    @discardableResult
    private func start(_ key: Key, priority: TaskPriority = .userInitiated) -> Task<Value?, Never> {
        let fetch = self.fetch
        let task = Task<Value?, Never>(priority: priority) {
            await fetch(key)
        }
        inFlight[key] = task

        // Recording the result has to happen on the actor, and cannot be done
        // inside the task above without re-entering it — so a second, tiny
        // task waits on the first and files the answer.
        filing[key] = Task { await self.finish(key, task: task) }
        return task
    }

    /// Files a completed fetch, unless a newer fetch for the same key has replaced it.
    ///
    /// A `nil` result clears the in-flight entry without caching anything.
    ///
    /// - Parameters:
    ///   - key: The key that was fetched.
    ///   - task: The fetch whose value to file.
    private func finish(_ key: Key, task: Task<Value?, Never>) async {
        let value = await task.value
        // A newer fetch may have replaced this one while it ran; only the
        // current one gets to write.
        guard inFlight[key] == task else { return }
        inFlight[key] = nil
        filing[key] = nil

        guard let value else { return }   // failures are not cached
        cache[key] = Entry(value: value, storedAt: clock.now, lastUsed: clock.now)
        evictIfNeeded()
    }

    /// Drops least recently used values until the cache is back within ``capacity``.
    private func evictIfNeeded() {
        guard cache.count > capacity else { return }
        let ordered = cache.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (key, _) in ordered.prefix(cache.count - capacity) {
            cache[key] = nil
        }
    }
}
