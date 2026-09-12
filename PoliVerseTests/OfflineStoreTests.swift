import Foundation
import Testing
@testable import PoliVerse

/// What survives losing signal.
///
/// Before this, only courses and rooms persisted. The agenda and the libretto
/// vanished — worse, `CareerService` actively wiped itself on a failed load,
/// so going into a basement replaced a student's exam record with an empty
/// screen.
@Suite("Offline store")
struct OfflineStoreTests {
    /// `nonisolated`: the project defaults types to MainActor, and a
    /// main-actor-isolated Codable conformance cannot satisfy a Sendable
    /// requirement.
    private nonisolated struct Payload: Codable, Equatable, Sendable {
        let value: String
    }

    private func store(_ name: String = #function) -> OfflineStore {
        // A directory of its own per test, so tests cannot see each other.
        OfflineStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-\(UUID().uuidString)", isDirectory: true))
    }

    @Test("What is saved comes back")
    func roundTrip() {
        let store = store()
        store.save(Payload(value: "a"), as: "thing", account: "123")
        #expect(store.load(Payload.self, as: "thing", account: "123")?.value.value == "a")
    }

    /// The trap the career switcher introduced: one person has several
    /// matricole, and the closed career's libretto must never appear under the
    /// active one.
    @Test("Cached data does not leak between accounts")
    func perAccount() {
        let store = store()
        store.save(Payload(value: "triennale"), as: "libretto", account: "986617")
        store.save(Payload(value: "magistrale"), as: "libretto", account: "332218")

        #expect(store.load(Payload.self, as: "libretto", account: "986617")?.value.value == "triennale")
        #expect(store.load(Payload.self, as: "libretto", account: "332218")?.value.value == "magistrale")
        #expect(store.load(Payload.self, as: "libretto", account: "999")?.value == nil)
    }

    /// Age is not decoration: the UI has to say "updated two days ago" rather
    /// than present stale data as current.
    @Test("A cached value knows how old it is")
    func age() {
        let store = store()
        store.save(Payload(value: "a"), as: "thing", account: "1")
        let entry = store.load(Payload.self, as: "thing", account: "1")
        #expect(entry != nil)
        #expect(entry!.age < 5)
    }

    @Test("A missing entry is nil rather than an empty value")
    func missing() {
        #expect(store().load(Payload.self, as: "nothing", account: "1") == nil)
    }

    /// A shape change between releases must not crash or resurrect nonsense.
    @Test("Unreadable data is discarded rather than half-decoded")
    func corrupt() {
        let store = store()
        store.save(Payload(value: "a"), as: "thing", account: "1")
        store.write(Data("not json".utf8), as: "thing", account: "1")
        #expect(store.load(Payload.self, as: "thing", account: "1") == nil)
    }

    @Test("Clearing one account leaves the others")
    func clearAccount() {
        let store = store()
        store.save(Payload(value: "a"), as: "thing", account: "1")
        store.save(Payload(value: "b"), as: "thing", account: "2")
        store.clear(account: "1")
        #expect(store.load(Payload.self, as: "thing", account: "1") == nil)
        #expect(store.load(Payload.self, as: "thing", account: "2") != nil)
    }

    @Test("Clearing everything empties the store")
    func clearAll() {
        let store = store()
        store.save(Payload(value: "a"), as: "thing", account: "1")
        store.clearAll()
        #expect(store.load(Payload.self, as: "thing", account: "1") == nil)
    }

    /// Sample data must never reach the disk, or turning the toggle off leaves
    /// invented courses behind that look real.
    @Test("An account of nil is not written")
    func refusesAnonymous() {
        let store = store()
        store.save(Payload(value: "a"), as: "thing", account: nil)
        #expect(store.load(Payload.self, as: "thing", account: nil) == nil)
    }
}

/// How the UI describes what it is showing.
@Suite("Freshness")
struct FreshnessTests {
    @Test("Data fetched moments ago is simply current")
    func current() {
        #expect(Freshness(age: 20, isOnline: true).label == nil)
    }

    /// Offline with recent data still deserves a word: the user needs to know
    /// nothing new is arriving.
    @Test("Offline is always stated, however fresh the data")
    func offline() {
        let freshness = Freshness(age: 20, isOnline: false)
        #expect(freshness.label?.contains("Offline") == true)
    }

    @Test("Old data is described by its age")
    func stale() {
        #expect(Freshness(age: 3600 * 5, isOnline: true).label?.contains("ore") == true)
        #expect(Freshness(age: 86400 * 2, isOnline: true).label?.contains("giorni") == true)
    }

    /// Never seen is not the same as old, and must not be reported as "0
    /// minutes ago".
    @Test("Data never fetched says so")
    func never() {
        #expect(Freshness(age: nil, isOnline: false).label?.contains("Offline") == true)
        #expect(Freshness(age: nil, isOnline: true).label == nil)
    }
}

/// A cached event must not be able to crash the calendar.
@Suite("Cached agenda safety")
struct CachedAgendaTests {
    /// `isOngoing` forms `start...end`, which traps on an inverted range. The
    /// initialiser clamps, but synthesised `Codable` would bypass it — so a
    /// file written by an older build, or a corrupted one, could reintroduce
    /// the crash this type was fixed for.
    @Test("An inverted range in cached data is clamped on decode")
    func clampsOnDecode() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let json = """
        {"id": 1, "title": "Lezione", "start": \(start.timeIntervalSinceReferenceDate),
         "end": \(start.addingTimeInterval(-3600).timeIntervalSinceReferenceDate),
         "kind": 1, "tags": []}
        """
        let event = try JSONDecoder().decode(AgendaEvent.self, from: Data(json.utf8))
        #expect(event.end >= event.start)
    }

    @Test("A normal event round-trips unchanged")
    func roundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = AgendaEvent(
            id: 7, title: "Analisi", start: start,
            end: start.addingTimeInterval(7200), kind: .lecture, room: "3.0.1")
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgendaEvent.self, from: data)
        #expect(decoded == event)
    }
}
