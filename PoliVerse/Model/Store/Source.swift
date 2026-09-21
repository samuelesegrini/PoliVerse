import Foundation

/// What a source is handed when it is asked to fetch.
///
/// Passed in rather than captured, so the same source instance works for a
/// signed-in account, for sample data and for a fixture without knowing which
/// it is looking at.
nonisolated struct Env: Sendable {
    let http: any HTTP
    let matricola: String?
    let isSample: Bool
}

/// Everything a feature has to say about one piece of remote data.
///
/// This is the whole of what porting a service costs: name it, say how long a
/// fetch stays good for, say how to fetch it, and say what it looks like when
/// the app is showing sample data. The window, the offline copy, the error
/// text, the age on screen, the signpost and the sample substitution are
/// ``Store``'s, once, rather than each service's, nineteen times.
///
/// `fetch` is deliberately `nonisolated` and `async`: decoding a payload is
/// work the main actor has no business doing, and every current service pays
/// for that by hand through ``BackgroundJSON``.
nonisolated protocol Source: Sendable {
    associatedtype Value: Codable & Sendable

    /// Names the offline file, the log line and the freshness registration.
    /// Changing it discards that service's cache, which is the correct
    /// behaviour when its shape has changed.
    static var id: String { get }
    /// How long a successful fetch suppresses the next one.
    static var ttl: TimeInterval { get }
    /// The signpost to time this load under, if it is one of the few the
    /// performance report names. The system caps how many it keeps, so most
    /// sources leave this nil — see ``PerfSignpost``.
    static var signpost: PerfSignpost.Name? { get }

    func fetch(_ env: Env) async throws -> Value

    /// What this service looks like with sample data. Required, not optional:
    /// the app used to decide that per call site, and twenty-three `if
    /// useMockData` branches across the screens is what that cost.
    func sample() -> Value

    /// Applies whatever this device remembers on top of a value, whether it
    /// came from the network, from the cache or from ``sample()``.
    ///
    /// Exists for read state: a notice marked read in PoliVerse is a local
    /// fact, and it has to survive every one of those three paths or it
    /// reverts on the next refresh.
    func adjust(_ value: Value) -> Value
}

/// `nonisolated` throughout: the target defaults to main-actor isolation, and
/// a default implementation that picked that up would drag every conforming
/// source onto the main actor with it — which is exactly what `fetch` is shaped
/// to avoid.
extension Source {
    nonisolated static var ttl: TimeInterval { LoadWindow.defaultInterval }
    nonisolated static var signpost: PerfSignpost.Name? { nil }
    nonisolated func adjust(_ value: Value) -> Value { value }
}
