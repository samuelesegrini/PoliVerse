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
nonisolated struct Whole: Hashable, Sendable {
    /// The one key.
    init() {}
}

/// Where a ``Loader`` keeps what it fetched.
nonisolated enum Persistence: Sendable {
    /// In memory only: public data, or data another file already keeps.
    case memory
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
    nonisolated static var persistence: Persistence { .offline }
    nonisolated static var capacity: Int { 128 }
    nonisolated static var signpost: PerfSignpost.Name? { nil }
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
    nonisolated func save(_ value: Value, to offline: OfflineStore, as name: String, account: String) {}

    nonisolated func read(from offline: OfflineStore, as name: String,
                          account: String) async -> (value: Value, age: TimeInterval)? { nil }
}

extension Resource where Value: Codable {
    nonisolated func save(_ value: Value, to offline: OfflineStore, as name: String, account: String) {
        offline.save(value, as: name, account: account)
    }

    nonisolated func read(from offline: OfflineStore, as name: String,
                          account: String) async -> (value: Value, age: TimeInterval)? {
        await offline.loaded(Value.self, as: name, account: account).map { ($0.value, $0.age) }
    }
}
