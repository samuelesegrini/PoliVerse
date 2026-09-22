import Foundation
import OSLog

/// The ``Source`` for the Politecnico's news.
///
/// `GET {agenda}/v1/persona/news` over a window from a month behind to a year ahead —
/// wider than the official client's, because news published last week is still news to
/// someone opening the app today, and the endpoint filters server-side.
///
/// Unlike the agenda's other calls this one is not scoped to a matricola: it is
/// `persona`, so the token alone identifies the reader.
///
/// The path and query are verified from the official client; the body's field names are
/// read leniently and its shape is logged in debug builds.
nonisolated struct NewsSource: Source {
    /// Names the offline record and the log category.
    static let id = "news"
    /// Fifteen minutes: the university publishes a handful of items a week.
    static let ttl: TimeInterval = 900

    /// Diagnostic log for this type, under the `news` category.
    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "news")

    /// The items, and whether the endpoint answered with something this decoder could not
    /// read.
    ///
    /// Carried together rather than as two properties on the model, because unreadability is
    /// a fact about this payload: held apart, an empty list from a clean fetch and an empty
    /// list from a garbled one would be indistinguishable once either was cached.
    struct Payload: Codable, Sendable, Equatable {
        /// The current items, newest first by ``NewsItem/displayDate``.
        var items: [NewsItem] = []
        /// Whether the payload carried rows the decoder could not read. An empty array is a
        /// quiet week; an unreadable body is a bug, and the two must not look alike.
        var unreadable = false
    }

    /// The moment the window is measured from. Fixed in tests, which would otherwise assert
    /// against a window that moves with the clock.
    var now: @Sendable () -> Date = { .now }

    /// Fetches the news for the window, keeping only what is still posted.
    ///
    /// - Parameter env: The transport.
    /// - Returns: The items, newest first, flagged unreadable when the payload carried rows
    ///   the decoder could not read.
    /// - Throws: ``APIError``.
    func fetch(_ env: Env) async throws -> Payload {
        let calendar = PoliMiDate.romeCalendar
        let now = now()
        // A month behind, a year ahead. The official app asks for today
        // forward, but news published last week is still news to someone
        // opening the app today, and the cost of the wider window is nil — the
        // endpoint filters server-side.
        let from = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let to = calendar.date(byAdding: .year, value: 1, to: now) ?? now

        let data = try await env.http.data(for: APIRequest(
            host: .agenda,
            path: "/v1/persona/news",
            query: [
                .init(name: "start_date", value: PoliMiDate.queryString(from)),
                .init(name: "end_date", value: PoliMiDate.queryString(to)),
            ]
        ))
        #if DEBUG
        Self.log.notice("news payload shape: \(JSONShape.describe(data), privacy: .public)")
        #endif

        let response = try await BackgroundJSON.decode(NewsResponse.self, from: data)
        let current = response.items
            .filter { $0.isCurrent(now: now) }
            .sorted { ($0.displayDate ?? .distantPast) > ($1.displayDate ?? .distantPast) }
        // An empty array is a quiet week; an unreadable body is a bug, and the
        // two must not be shown as the same thing.
        let unreadable = response.items.isEmpty && !(response.raw.arrayValue?.isEmpty ?? false)
        Self.log.notice("news: \(response.items.count, privacy: .public) returned, \(current.count, privacy: .public) current")
        return Payload(items: current, unreadable: unreadable)
    }

    /// The sample news items.
    func sample() -> Payload {
        Payload(items: NewsItem.samples())
    }
}
