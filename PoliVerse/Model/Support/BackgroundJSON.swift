import Foundation

/// JSON decoding that does not run on the main actor.
///
/// Under this project's settings — main actor by default, and approachable
/// concurrency, which makes a plain `nonisolated async` function run on its
/// *caller's* actor (SE-0461) — every `JSONDecoder().decode` in a service ran
/// on the main thread, however `nonisolated` the client that fetched the bytes.
/// A calendar or a gradebook payload is the kind of work that shows up as a
/// dropped frame during a pull-to-refresh.
///
/// `@concurrent` is the explicit way off: the decode runs on the global
/// executor and only the `Sendable` result comes back.
/// See `docs/metrickit-performance.md` §3.3, H1–H2.
nonisolated enum BackgroundJSON {
    @concurrent
    static func decode<T: Decodable & Sendable>(
        _ type: T.Type, from data: Data, iso8601Dates: Bool = false
    ) async throws -> T {
        let decoder = JSONDecoder()
        if iso8601Dates { decoder.dateDecodingStrategy = .iso8601 }
        return try decoder.decode(T.self, from: data)
    }
}
