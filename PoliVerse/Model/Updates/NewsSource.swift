import Foundation
import OSLog

/// News from the Politecnico.
///
/// `GET {agenda}/v1/persona/news?start_date=…&end_date=…` — path and query
/// parameters verified from the official bundle, response body not. The payload
/// is read leniently and its *shape* is logged, so one run on a real account
/// settles the field names.
///
/// Unlike the agenda's other calls this one is not scoped to a matricola: it is
/// `persona`, not `matricola/{m}`, so the token alone identifies the reader.
nonisolated struct NewsSource: Source {
    static let id = "news"
    /// Fifteen minutes: the ateneo publishes a handful of items a week.
    static let ttl: TimeInterval = 900

    private static let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "news")

    /// The items, plus whether the endpoint answered with something this
    /// decoder could not read.
    ///
    /// Carried together rather than as two properties on the service, because
    /// "unreadable" is a fact about *this* payload: held apart, an empty list
    /// from a successful fetch and an empty list from a garbled one would be
    /// indistinguishable the moment either was cached.
    struct Payload: Codable, Sendable, Equatable {
        var items: [NewsItem] = []
        var unreadable = false
    }

    /// Fixed in tests, which would otherwise assert against a window that moves
    /// with the clock.
    var now: @Sendable () -> Date = { .now }

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

    func sample() -> Payload {
        Payload(items: NewsItem.samples())
    }
}
