import Foundation

/// The context a ``Source`` is handed when it is asked to fetch.
///
/// Passed in rather than captured, so one source instance serves a signed-in
/// account, sample data and a fixture without knowing which it is looking at.
nonisolated struct Env: Sendable {
    /// The transport to issue requests through.
    let http: any HTTP
    /// The signed-in matricola, or `nil` when signed out.
    let matricola: String?
    /// `true` when the app is showing representative data rather than a student's own.
    let isSample: Bool
}

/// Everything a feature has to declare about one piece of remote data.
///
/// A conformance names the data, states how long a fetch stays good for, says
/// how to fetch it and says what it looks like under sample data. The load
/// window, the offline copy, the error text, the age shown on screen, the
/// signpost and the sample substitution all belong to ``Store``.
///
/// ``fetch(_:)`` is `nonisolated` and `async` so that decoding runs off the main
/// actor.
nonisolated protocol Source: Sendable {
    /// The decoded shape this source produces. `Codable` because ``Store`` persists
    /// it as the offline copy.
    associatedtype Value: Codable & Sendable

    /// Names the offline file, the log category and the freshness registration.
    ///
    /// Changing it discards this service's cache, which is the intended behaviour
    /// when ``Value`` changes shape.
    static var id: String { get }
    /// How long a successful fetch suppresses the next one. Defaults to
    /// ``LoadWindow/defaultInterval``.
    static var ttl: TimeInterval { get }
    /// The signpost to time this load under, or `nil` not to time it.
    ///
    /// The system caps how many signposts it retains, so only the loads named in the
    /// performance report set this. See ``PerfSignpost``.
    static var signpost: PerfSignpost.Name? { get }

    /// Fetches and decodes the current value.
    ///
    /// - Parameter env: The transport, matricola and sample flag for this load.
    /// - Returns: The freshly decoded value.
    /// - Throws: Whatever the transport or the decoder raises. ``Store`` turns it
    ///   into a message, and treats a cancellation as neither failure nor success.
    func fetch(_ env: Env) async throws -> Value

    /// What this service looks like under sample data.
    ///
    /// Required rather than optional, so no call site has to branch on whether
    /// sample data is in use.
    func sample() -> Value

    /// Layers whatever this device remembers on top of a value, whichever of the
    /// three origins it came from — network, offline copy or ``sample()``.
    ///
    /// Carries local read state: a notice marked read in PoliVerse is a device-local
    /// fact, and has to survive all three paths or it reverts on the next refresh.
    ///
    /// - Parameter value: The value as it arrived.
    /// - Returns: The value with local state applied. The default returns it
    ///   unchanged.
    func adjust(_ value: Value) -> Value
}

/// Defaults for the parts of ``Source`` most services do not customise.
///
/// Every member is `nonisolated`: the target defaults to main-actor isolation,
/// and a default that inherited it would pull conforming sources onto the main
/// actor.
extension Source {
    /// Defaults to ``LoadWindow/defaultInterval``.
    nonisolated static var ttl: TimeInterval { LoadWindow.defaultInterval }
    /// Defaults to untimed.
    nonisolated static var signpost: PerfSignpost.Name? { nil }
    /// Defaults to returning the value unchanged.
    nonisolated func adjust(_ value: Value) -> Value { value }
}
