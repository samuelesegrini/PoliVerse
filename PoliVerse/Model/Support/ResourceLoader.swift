import Foundation
import OSLog

/// Fetch-once, share, cache, prefetch.
///
/// ## Why this exists
///
/// Four services had grown their own answer to "have I already fetched this?"
/// — ``LoadWindow``, an `isLoading` flag, a `loadedKey` string, a dictionary
/// keyed by id — each subtly different, none of them able to do the two things
/// that actually matter on a phone:
///
/// - **Coalesce.** Two screens asking for the same thing at once should cost
///   one request. An `isLoading` flag makes the second caller give up and
///   render nothing, which is why opening a room from search while the rooms
///   list was still loading showed an empty screen.
/// - **Prefetch.** Warming the next thing while the user reads this one is the
///   difference between a tap that feels instant and one that spins. Nothing
///   in the app could express it.
///
/// ## Isolation
///
/// An `actor`, so the cache and the in-flight table are consistent without a
/// lock, and `@concurrent` work runs off the main actor. The project defaults
/// to `MainActor` isolation, so this must be explicit or the fetches would
/// serialise behind the UI.
///
/// ## Cancellation, which is the subtle part
///
/// The work runs in an **unstructured** `Task` held by the actor, and callers
/// await its value. That is deliberate: with structured concurrency, a caller
/// that goes away cancels the work, and any *other* screen waiting on the same
/// resource loses it too. Awaiting a stored task means a caller can vanish
/// without taking the shared fetch with it.
actor ResourceLoader<Key: Hashable & Sendable, Value: Sendable> {
    /// What the loader does when it has nothing cached. Returning nil means
    /// "failed" — and failures are deliberately not cached, or one flaky
    /// moment poisons the resource for the lifetime of the app.
    typealias Fetch = @Sendable (Key) async -> Value?

    private struct Entry {
        let value: Value
        let storedAt: ContinuousClock.Instant
        var lastUsed: ContinuousClock.Instant
    }

    private let fetch: Fetch
    private let lifetime: Duration
    private let capacity: Int
    private let clock = ContinuousClock()
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "loader")

    private var cache: [Key: Entry] = [:]
    private var inFlight: [Key: Task<Value?, Never>] = [:]
    /// The task that files a result once its fetch returns.
    ///
    /// Tracked separately from ``inFlight`` because awaiting a fetch is not
    /// the same as the cache having been written: the write happens in a
    /// second task, and ``settle()`` has to wait for *that* one or it spins
    /// on an entry nothing will ever clear.
    private var filing: [Key: Task<Void, Never>] = [:]

    /// - Parameters:
    ///   - lifetime: how long a value stays good. Five minutes by default,
    ///     comfortably longer than a tab switch.
    ///   - capacity: how many values to hold. Bounded, or a long session in
    ///     the rooms list keeps every floor plan it ever showed.
    init(
        lifetime: Duration = .seconds(300),
        capacity: Int = 128,
        fetch: @escaping Fetch
    ) {
        self.lifetime = lifetime
        self.capacity = capacity
        self.fetch = fetch
    }

    var count: Int { cache.count }

    func isCached(_ key: Key) -> Bool {
        guard let entry = cache[key] else { return false }
        return clock.now - entry.storedAt < lifetime
    }

    /// The value, fetching if needed and joining any fetch already running.
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

    /// Warms a value without waiting for it.
    ///
    /// Returns as soon as the work is queued — a prefetch that blocked would
    /// defeat the point. Runs at background priority so it yields to anything
    /// the user is actually waiting on.
    func prefetch(_ key: Key) {
        guard !isCached(key), inFlight[key] == nil else { return }
        _ = start(key, priority: .background)
    }

    func prefetch(_ keys: some Sequence<Key>) {
        for key in keys { prefetch(key) }
    }

    /// Waits for everything in flight to finish.
    ///
    /// Prefetches run at background priority, which the system is free to
    /// starve for a long time when anything else is busy — desirable in the
    /// app, unusable in a test that would otherwise sleep and hope. The
    /// background refresh uses it too: a thirty-second window is no place to
    /// return before the work is actually done.
    func settle() async {
        // Loops because a caller may queue more while we wait; terminates
        // because each pass awaits tasks that clear their own entry.
        while !filing.isEmpty {
            for task in Array(filing.values) { await task.value }
        }
    }

    func invalidate(_ key: Key) {
        cache[key] = nil
    }

    /// Empties the cache and abandons anything in flight. For sign-out: the
    /// next person on this device must not inherit the last one's data.
    func clear() {
        cache.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        for task in filing.values { task.cancel() }
        filing.removeAll()
    }

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

    /// Least recently used first — the room the user scrolled past ten
    /// screens ago is the one they are least likely to open.
    private func evictIfNeeded() {
        guard cache.count > capacity else { return }
        let ordered = cache.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (key, _) in ordered.prefix(cache.count - capacity) {
            cache[key] = nil
        }
    }
}
