import Foundation
import Observation
import OSLog

/// News from the Politecnico.
///
/// `GET {agenda}/v1/persona/news?start_date=…&end_date=…` — path and query
/// parameters verified from the official bundle, response body not. As with
/// ``NoticeService``, the payload is read leniently and its *shape* is logged
/// so one run on a real account settles the field names.
///
/// Unlike the agenda's other calls this one is not scoped to a matricola: it
/// is `persona`, not `matricola/{m}`, so the token alone identifies the reader.
@Observable
final class NewsService {
    private(set) var items: [NewsItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// The endpoint answered with something this decoder could not read —
    /// distinct from there being no news, and not to be shown as the same.
    private(set) var payloadUnreadable = false

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "news")
    private var window = LoadWindow()
    private var slot = CachedSlot<[NewsItem]>(name: "news")
    private(set) var age: TimeInterval?

    private var source: String {
        session.useMockData ? "mock" : (session.student?.matricola ?? "anonymous")
    }

    /// The few most recent items, for the Home summary.
    var highlights: [NewsItem] { Array(items.prefix(5)) }

    init(session: Session) {
        self.session = session
    }

    private func restoreCache() {
        guard let cached = slot.restore(for: session.student?.matricola) else { return }
        items = cached
        age = slot.age
    }

    func load(force: Bool = false) async {
        guard !isLoading, window.shouldLoad(force: force, source: source) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        restoreCache()

        if session.useMockData {
            items = MockData.news()
            payloadUnreadable = false
            window.markLoaded(source: source)
            return
        }

        let calendar = PoliMiDate.romeCalendar
        let now = Date.now
        // A month behind, a year ahead. The official app asks for today
        // forward, but news published last week is still news to someone
        // opening the app today, and the cost of the wider window is nil —
        // the endpoint filters server-side.
        let from = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let to = calendar.date(byAdding: .year, value: 1, to: now) ?? now

        do {
            let data = try await session.api.send(
                APIRequest(
                    host: .agenda,
                    path: "/v1/persona/news",
                    query: [
                        .init(name: "start_date", value: PoliMiDate.queryString(from)),
                        .init(name: "end_date", value: PoliMiDate.queryString(to)),
                    ]
                )
            )
            log.notice("news payload shape: \(JSONShape.describe(data), privacy: .public)")

            let response = try JSONDecoder().decode(NewsResponse.self, from: data)
            let current = response.items.filter { $0.isCurrent(now: now) }
            items = current.sorted {
                ($0.displayDate ?? .distantPast) > ($1.displayDate ?? .distantPast)
            }
            payloadUnreadable = response.items.isEmpty
                && !(response.raw.arrayValue?.isEmpty ?? false)
            log.notice("news: \(response.items.count, privacy: .public) returned, \(self.items.count, privacy: .public) current")
            window.markLoaded(source: source)
            slot.save(items, for: session.useMockData ? nil : session.student?.matricola)
            age = slot.age
        } catch {
            log.error("News failed: \(error.localizedDescription)")
            errorMessage = userFacingMessage(error)
        }
    }
}
