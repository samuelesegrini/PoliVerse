import Foundation

/// JSON decoding that runs off the main actor.
///
/// The target defaults to main-actor isolation, and under approachable concurrency
/// a plain `nonisolated async` function runs on its caller's actor, so an ordinary
/// `JSONDecoder().decode` inside a service decodes on the main thread however
/// `nonisolated` the client that fetched the bytes. The `@concurrent` attribute on
/// ``decode(_:from:iso8601Dates:)`` moves the work to the global executor, and only
/// the `Sendable` result returns.
///
/// Services built on ``Store`` get this for free through ``Source/fetch(_:)``; this
/// type serves the models that fetch by hand.
///
/// See `docs/metrickit-performance.md` §3.3.
nonisolated enum BackgroundJSON {
    /// Decodes a value on the global executor.
    ///
    /// - Parameters:
    ///   - type: The shape to decode.
    ///   - data: The bytes to decode from.
    ///   - iso8601Dates: Decodes dates with `.iso8601` rather than the default
    ///     strategy.
    /// - Returns: The decoded value.
    /// - Throws: Whatever `JSONDecoder` raises.
    @concurrent
    static func decode<T: Decodable & Sendable>(
        _ type: T.Type, from data: Data, iso8601Dates: Bool = false
    ) async throws -> T {
        let decoder = JSONDecoder()
        if iso8601Dates { decoder.dateDecodingStrategy = .iso8601 }
        return try decoder.decode(T.self, from: data)
    }
}
