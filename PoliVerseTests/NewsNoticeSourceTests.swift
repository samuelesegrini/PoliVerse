import Foundation
import Testing
@testable import PoliVerse

/// The two services ported onto ``Store`` first, tested through their real
/// endpoints for the first time.
///
/// ``NewsTests`` and ``NoticeTests`` already pin the decoders, which is the
/// part that was reachable before. These pin the part that was not: the request
/// actually sent, and what the service does with what comes back.
@Suite("Ported sources")
@MainActor
struct NewsNoticeSourceTests {
    private func offline() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("ported-\(UUID().uuidString)", isDirectory: true))
    }

    // MARK: - News

    /// The path and both query parameters come from the official bundle. Sent
    /// wrongly, the endpoint answers with an empty list rather than an error,
    /// so nothing on screen would say the app had asked the wrong question.
    @Test("News asks the verified path, a month back and a year forward")
    func newsRequest() async throws {
        let http = FixtureHTTP(["/v1/persona/news": Data("[]".utf8)])
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var source = NewsSource()
        source.now = { now }

        _ = try await source.fetch(Env(http: http, matricola: "111", isSample: false))

        let request = try #require(await http.requests.first)
        #expect(request.host == .agenda)
        #expect(request.path == "/v1/persona/news")
        let start = try #require(request.query.first { $0.name == "start_date" }?.value)
        let end = try #require(request.query.first { $0.name == "end_date" }?.value)
        let calendar = PoliMiDate.romeCalendar
        #expect(start == PoliMiDate.queryString(
            try #require(calendar.date(byAdding: .month, value: -1, to: now))))
        #expect(end == PoliMiDate.queryString(
            try #require(calendar.date(byAdding: .year, value: 1, to: now))))
    }

    /// An empty inbox and a garbled body must not look the same. They used to
    /// the moment either was cached, which is why the flag travels with the
    /// items rather than beside them.
    @Test("An empty list is quiet; an unreadable body is flagged")
    func newsUnreadable() async throws {
        let quiet = try await NewsSource().fetch(
            Env(http: FixtureHTTP(["/v1/persona/news": Data("[]".utf8)]),
                matricola: "111", isSample: false))
        #expect(quiet.items.isEmpty)
        #expect(quiet.unreadable == false)

        let garbled = try await NewsSource().fetch(
            Env(http: FixtureHTTP(["/v1/persona/news": Data(#"{"unexpected": 1}"#.utf8)]),
                matricola: "111", isSample: false))
        #expect(garbled.items.isEmpty)
        #expect(garbled.unreadable)
    }

    @Test("News reaches the screens through the model unchanged")
    func newsThroughModel() async {
        let payload = Data("""
        [{"news_id": 1, "title": {"it": "Bandi"}, "date_start": "2020-01-01T09:00:00",
          "date_end": "2099-01-01T09:00:00"}]
        """.utf8)
        let account = StubAccount(http: FixtureHTTP(["/v1/persona/news": payload]))
        let news = NewsModel(account: account)

        await news.load()

        #expect(news.items.count == 1)
        #expect(news.highlights.count == 1)
        #expect(news.errorMessage == nil)
        #expect(news.payloadUnreadable == false)
    }

    // MARK: - Notices

    @Test("Notices ask the app host for the notifications list")
    func noticeRequest() async throws {
        let http = FixtureHTTP(["/v1/notifications": Data("[]".utf8)])

        _ = try await NoticeSource().fetch(Env(http: http, matricola: "111", isSample: false))

        let request = try #require(await http.requests.first)
        #expect(request.host == .app)
        #expect(request.path == "/v1/notifications")
    }

    /// The reason ``Source/adjust(_:)`` is on the protocol at all: read state
    /// is a local fact, and it has to be layered on whichever of the three
    /// paths the value arrived by, or it reverts on the next refresh.
    @Test("A notice read in PoliVerse stays read across a refresh")
    func readStateSurvivesRefresh() async throws {
        let remembered = RememberedReads()
        let payload = Data("""
        [{"id_notice": "n1", "titolo": "Uno"}, {"id_notice": "n2", "titolo": "Due"}]
        """.utf8)
        let account = StubAccount(http: FixtureHTTP(["/v1/notifications": payload]))
        let notices = NoticeModel(account: account, readLocally: remembered.state)

        await notices.load()
        #expect(notices.unreadCount == 2)

        let first = try #require(notices.notices.first)
        notices.markRead(first)
        #expect(notices.unreadCount == 1)

        // The refetch returns both notices as unread, exactly as the server
        // sent them the first time.
        await notices.load(force: true)
        #expect(notices.unreadCount == 1)
    }

    /// The same guarantee on the path the app actually takes on launch: the
    /// value comes off disk, not off the wire.
    @Test("Read state is applied to the offline copy too")
    func readStateAppliesToCache() async throws {
        let remembered = RememberedReads()
        remembered.insert(["n1"])
        let offline = offline()
        let seeded = NoticesResponse.extract(from: try JSONDecoder().decode(
            JSONValue.self,
            from: Data(#"[{"id_notice":"n1","titolo":"Uno"},{"id_notice":"n2","titolo":"Due"}]"#.utf8)))
        #expect(seeded.count == 2)
        offline.save(NoticeSource.Payload(notices: seeded), as: NoticeSource.id, account: "111")

        var source = NoticeSource()
        source.readLocally = remembered.state
        let store = Store(source,
                          account: StubAccount(matricola: "111",
                                               http: FixtureHTTP.failing(APIError.cancelled)),
                          offline: offline)

        await store.load()

        let held = try #require(store.value)
        #expect(held.notices.count == 2)
        #expect(held.notices.first { $0.id == "n1" }?.isRead == true)
        #expect(held.notices.first { $0.id == "n2" }?.isRead == false)
    }

    @Test("Mark all read clears the count")
    func markAllRead() async {
        let payload = Data("""
        [{"id_notice": "n1", "titolo": "Uno"}, {"id_notice": "n2", "titolo": "Due"}]
        """.utf8)
        let account = StubAccount(http: FixtureHTTP(["/v1/notifications": payload]))
        let notices = NoticeModel(account: account, readLocally: RememberedReads().state)

        await notices.load()
        notices.markAllRead()

        #expect(notices.unreadCount == 0)
    }

    /// Read state that lives in the test rather than in `UserDefaults`, so the
    /// suite leaves nothing behind and two tests cannot see each other's marks.
    private nonisolated final class RememberedReads: @unchecked Sendable {
        private let lock = NSLock()
        private var identifiers: Set<String> = []

        func insert(_ added: Set<String>) {
            lock.withLock { identifiers.formUnion(added) }
        }

        var state: NoticeSource.ReadState {
            NoticeSource.ReadState(
                identifiers: { [self] in lock.withLock { identifiers } },
                insert: { [weak self] in self?.insert($0) }
            )
        }
    }
}
