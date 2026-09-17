import Foundation
import Testing
@testable import PoliVerse

/// Phase 2 of `docs/metrickit-performance.md` moved work off the main thread
/// and out of hot loops. Each change keeps a promise the old code kept by
/// accident; these make the promises explicit.
@Suite("Main-thread work")
struct MainThreadWorkTests {
    private nonisolated struct Payload: Codable, Equatable, Sendable {
        let value: String
    }

    private func store() -> OfflineStore {
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-\(UUID().uuidString)", isDirectory: true))
    }

    // MARK: OfflineStore, now writing on a queue

    @Test("A load straight after a save sees the save")
    func loadWaitsForWrite() {
        let store = store()
        store.save(Payload(value: "first"), as: "x", account: "111")
        store.save(Payload(value: "second"), as: "x", account: "111")
        #expect(store.load(Payload.self, as: "x", account: "111")?.value == Payload(value: "second"))
    }

    /// Sign-out clears the store. A save still queued from the last load must
    /// not put the student's record back afterwards.
    @Test("A queued save cannot outlive a clear")
    func clearWaitsForWrite() {
        let store = store()
        store.save(Payload(value: "record"), as: "x", account: "111")
        store.clear(account: "111")
        #expect(store.load(Payload.self, as: "x", account: "111") == nil)

        store.save(Payload(value: "record"), as: "x", account: "111")
        store.clearAll()
        #expect(store.load(Payload.self, as: "x", account: "111") == nil)
    }

    @Test("Account names are sanitised exactly as the regex did")
    func sanitisesAccount() {
        #expect(OfflineStore.safe("10-12_34") == "10-12_34")
        #expect(OfflineStore.safe("../etc/passwd") == "etcpasswd")
        #expect(OfflineStore.safe("Rossì 12") == "Ross12")
        #expect(OfflineStore.safe("") == "")
    }

    // MARK: Decoding off the main actor

    @Test("Background decoding reads ISO 8601 dates when asked")
    func decodesOffMain() async throws {
        nonisolated struct Stamped: Decodable, Sendable { let at: Date }
        let data = Data(#"{"at":"2027-01-15T08:00:00Z"}"#.utf8)
        let decoded = try await BackgroundJSON.decode(Stamped.self, from: data, iso8601Dates: true)
        #expect(decoded.at == Date(timeIntervalSince1970: 1_800_000_000))
    }

    // MARK: Agenda, indexed by day

    @Test("Events are grouped by Rome day and sorted within it")
    func indexesByDay() {
        let calendar = PoliMiDate.romeCalendar
        // 23:30 UTC in January is 00:30 the next day in Rome.
        let lateUTC = Date(timeIntervalSince1970: 1_800_000_000 + 15.5 * 3600)
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            AgendaEvent(id: 2, title: "B", start: morning.addingTimeInterval(3600), end: morning.addingTimeInterval(7200), kind: .lecture),
            AgendaEvent(id: 1, title: "A", start: morning, end: morning.addingTimeInterval(3600), kind: .lecture),
            AgendaEvent(id: 3, title: "C", start: lateUTC, end: lateUTC.addingTimeInterval(3600), kind: .deadline),
        ]

        let index = AgendaModel.index(events)
        #expect(index[calendar.startOfDay(for: morning)]?.map(\.id) == [1, 2])
        #expect(index[calendar.startOfDay(for: lateUTC)]?.map(\.id) == [3])
        #expect(index.count == 2)
    }

    // MARK: Regex cache

    @Test("A cached pattern matches like a fresh one, options included")
    func regexCache() {
        let sensitive = RegexCache.regex("abc")
        let insensitive = RegexCache.regex("abc", options: .caseInsensitive)
        #expect(sensitive !== insensitive)
        #expect(RegexCache.regex("abc") === sensitive)
        let text = "ABC"
        let range = NSRange(text.startIndex..., in: text)
        #expect(sensitive?.firstMatch(in: text, range: range) == nil)
        #expect(insensitive?.firstMatch(in: text, range: range) != nil)
        #expect(RegexCache.regex("(") == nil)
    }
}
