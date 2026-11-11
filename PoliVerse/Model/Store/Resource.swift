import Foundation

/// The context a ``Resource`` is handed when it is asked to fetch.
///
/// Passed in rather than captured, so one resource serves a signed-in account,
/// sample data and a fixture without knowing which it is looking at. Built on the
/// main actor from an ``Account``, which is main-actor isolated, and carried to the
/// ``Loader`` as a value.
nonisolated struct Env: Sendable {
    /// The transport to issue requests through.
    let http: any HTTP
    /// The signed-in matricola, or `nil` when signed out.
    let matricola: String?
    /// `true` when the app is showing representative data rather than a student's own.
    let isSample: Bool

    /// Whose data a load describes: the matricola, a marker for sample data, or
    /// `"anonymous"`. A held value for a different source is never served.
    var source: String { isSample ? "mock" : (matricola ?? "anonymous") }

    /// The context for data that belongs to nobody, such as a room's timetable.
    static func `public`(_ http: any HTTP = PublicHTTP()) -> Env {
        Env(http: http, matricola: nil, isSample: false)
    }
}

extension Env {
    /// The context for an account as it stands now.
    ///
    /// - Parameter account: The account to read.
    @MainActor
    init(_ account: any Account) {
        self.init(http: account.http, matricola: account.matricola, isSample: account.isSample)
    }
}

/// The key of a resource that has one value per account, such as the career.
nonisolated struct Whole: Hashable, Sendable, CaseIterable {
    /// The one key.
    init() {}

    /// The one value there is: as a ``Resource/Part``, it says "a single request".
    static var allCases: [Whole] { [Whole()] }
}

/// Where a ``Loader`` keeps what it fetched.
nonisolated enum Persistence: Sendable {
    /// In memory only: public data, or data another file already keeps.
    case memory
    /// Public data, shared across accounts in DiskCache.
    case publicDisk
    /// Also on disk per account, restored at the next launch before the network answers.
    case offline
}

/// Everything a feature declares about one kind of remote data.
///
/// A conformance names the data, states how long a fetch stays good for, says how
/// to fetch it and what it looks like under sample data. Joining a fetch already in
/// flight, the cache and its lifetime, the offline copy, the signpost and the sample
/// substitution belong to ``Loader``; the observable state a view reads belongs to
/// ``Query``.
///
/// ``fetch(_:env:previous:)`` is `@concurrent`: everything a fetch does besides
/// waiting — decoding, parsing a page, merging, sorting, indexing — runs on the
/// global pool, never on the main actor. With Approachable Concurrency a plain
/// `nonisolated async` function runs on its caller, so the attribute is what keeps
/// that work off the main thread.
nonisolated protocol Resource: Sendable {
    /// What one value is fetched for: a week, a room on a day, a course. ``Whole``
    /// for data with one value per account.
    associatedtype Key: Hashable & Sendable = Whole
    /// The shape this resource produces. A ``Persistence/offline`` resource's value
    /// must also be `Codable`, since the offline copy stores it.
    associatedtype Value: Sendable
    /// The pieces a value is fetched in, when it takes several requests that each
    /// fill a section of a screen: the career's libretto, its sittings, its counters.
    /// ``Whole`` for data that arrives in one request, which is the default, so a
    /// resource without parts declares nothing.
    associatedtype Part: Hashable & Sendable & CaseIterable = Whole

    /// Names the offline file, the log category and the signpost's owner.
    ///
    /// Changing it discards this resource's offline copy, which is the intended
    /// behaviour when ``Value`` changes shape.
    static var id: String { get }
    /// How long a successful fetch is served without asking again. Five minutes by
    /// default.
    static var ttl: TimeInterval { get }
    /// Whether a fetched value is also written to disk per account. `.offline` by
    /// default; ignored for a value that is not `Codable`.
    static var persistence: Persistence { get }
    /// How long one part is served without asking again. ``ttl`` by default; a
    /// resource whose parts age differently says so here, and a refresh then asks
    /// only for the parts that are old.
    ///
    /// - Parameter part: The part.
    static func maxAge(of part: Part) -> TimeInterval
    /// How long after a part failed before it is asked for again without the
    /// student asking. A minute by default.
    static var retryAfter: TimeInterval { get }
    /// How many keys the loader keeps in memory before dropping the least recently
    /// used. 128 by default.
    static var capacity: Int { get }
    /// The signpost to time a fetch under, or `nil` not to time it.
    ///
    /// The system caps how many signposts it retains, so only the loads named in the
    /// performance report set this. See ``PerfSignpost``.
    static var signpost: PerfSignpost.Name? { get }

    /// Fetches and builds the current value for one key, off the main actor.
    ///
    /// - Parameters:
    ///   - key: What to fetch.
    ///   - env: Whose data, through which transport.
    ///   - previous: What is held for this key, so a partial failure can keep the
    ///     part that did not arrive.
    /// - Returns: The value.
    @concurrent
    func fetch(_ key: Key, env: Env, previous: Value?) async throws -> Value

    /// Fetches several keys at once.
    ///
    /// The default fetches each key concurrently. A resource whose endpoint answers a
    /// span in one request — the agenda's weeks — overrides it.
    ///
    /// - Parameters:
    ///   - keys: What to fetch; never empty.
    ///   - env: Whose data, through which transport.
    ///   - previous: What is held for those keys.
    /// - Returns: A value per key. A key missing from the result is treated as failed.
    @concurrent
    func fetch(_ keys: [Key], env: Env, previous: [Key: Value]) async throws -> [Key: Value]

    /// Fetches some parts of one key, handing over what it has as each part answers.
    ///
    /// The loader calls this for a resource that declares a ``Part``. The default
    /// forwards to ``fetch(_:env:previous:)-(Key,_,_)`` and reports every requested
    /// part as arrived, so only a resource with real parts writes it.
    ///
    /// - Parameters:
    ///   - key: What to fetch.
    ///   - env: Whose data, through which transport.
    ///   - parts: The parts to ask for; never empty. A part left out is still good
    ///     and must not be requested.
    ///   - held: What is held for this key. The result is laid over it, so a part
    ///     not asked for, or failed, keeps what was there.
    ///   - progress: Where to report the value after each part answers.
    /// - Returns: The value, with the requested parts that answered and those that
    ///   failed.
    /// - Throws: When nothing worth showing came back.
    @concurrent
    func fetch(_ key: Key, env: Env, parts: Set<Part>, over held: Value?,
               progress: LoadProgress<Self>) async throws -> LoadProgress<Self>.Snapshot

    /// What a fetched part changed with respect to the copy held, by the identity
    /// of its items. Nothing by default: only a resource whose items keep their
    /// id from one answer to the next says so, through ``ChangeDetector``.
    ///
    /// - Parameters:
    ///   - part: The part that just answered.
    ///   - old: The value held before it did.
    ///   - new: The value with the answer in it.
    func changes(in part: Part, from old: Value, to new: Value) -> ChangeSet

    /// The value under sample data, never fetched and never written to disk; `nil`
    /// for public data, which is the same for everyone and is fetched as usual.
    ///
    /// - Parameter key: What is asked for.
    func sample(_ key: Key) -> Value?

    /// A last pass over a value before it is shown, for state kept on the device —
    /// notices read here, for one. Identity by default.
    ///
    /// - Parameter value: The fetched or restored value.
    func adjust(_ value: Value) -> Value

    /// The offline file's name for a key. ``id`` by default, which suits ``Whole``;
    /// a keyed resource with an offline copy gives each key its own.
    ///
    /// - Parameter key: The key.
    func storageName(for key: Key) -> String

    /// Writes a value's offline copy. Does nothing unless ``Value`` is `Codable`;
    /// provided, not written by conformances.
    func save(_ value: Value, to offline: OfflineStore, as name: String, account: String)

    /// Reads a value's offline copy off the caller. `nil` unless ``Value`` is
    /// `Codable`; provided, not written by conformances.
    func read(from offline: OfflineStore, as name: String, account: String) async -> (value: Value, age: TimeInterval)?
}

extension Resource {
    nonisolated static var ttl: TimeInterval { 300 }
    nonisolated static func maxAge(of part: Part) -> TimeInterval { ttl }
    nonisolated static var retryAfter: TimeInterval { 60 }
    nonisolated static var persistence: Persistence { .offline }
    nonisolated static var capacity: Int { 128 }
    nonisolated static var signpost: PerfSignpost.Name? { nil }
    nonisolated func changes(in part: Part, from old: Value, to new: Value) -> ChangeSet { ChangeSet() }
    nonisolated func sample(_ key: Key) -> Value? { nil }
    nonisolated func adjust(_ value: Value) -> Value { value }
    nonisolated func storageName(for key: Key) -> String { Self.id }

    @concurrent
    nonisolated func fetch(_ keys: [Key], env: Env, previous: [Key: Value]) async throws -> [Key: Value] {
        try await withThrowingTaskGroup(of: (Key, Value).self) { group in
            for key in keys {
                group.addTask(name: "\(Self.id) \(key)") {
                    (key, try await self.fetch(key, env: env, previous: previous[key]))
                }
            }
            var values: [Key: Value] = [:]
            for try await (key, value) in group { values[key] = value }
            return values
        }
    }
}

extension Resource {
    @concurrent
    nonisolated func fetch(_ key: Key, env: Env, parts: Set<Part>, over held: Value?,
                           progress: LoadProgress<Self>) async throws -> LoadProgress<Self>.Snapshot {
        .init(value: try await fetch(key, env: env, previous: held), arrived: parts, failed: [])
    }
}

extension Resource {
    nonisolated func save(_ value: Value, to offline: OfflineStore, as name: String, account: String) {}

    nonisolated func read(from offline: OfflineStore, as name: String,
                          account: String) async -> (value: Value, age: TimeInterval)? { nil }
}

extension Resource where Value: Codable {
    nonisolated func save(_ value: Value, to offline: OfflineStore, as name: String, account: String) {
        if Self.persistence == .publicDisk { DiskCache.save(value, as: name) }
        else { offline.save(value, as: name, account: account) }
    }

    nonisolated func read(from offline: OfflineStore, as name: String,
                          account: String) async -> (value: Value, age: TimeInterval)? {
        if Self.persistence == .publicDisk {
            return await Self.publicCopy(name)
        }
        return await offline.loaded(Value.self, as: name, account: account).map { ($0.value, $0.age) }
    }
}

extension Resource where Value: Codable {
    @concurrent
    private static func publicCopy(_ name: String) async -> (value: Value, age: TimeInterval)? {
        DiskCache.load(Value.self, as: name).map { ($0.value, Date.now.timeIntervalSince($0.storedAt)) }
    }
}
