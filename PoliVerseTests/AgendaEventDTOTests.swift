import Foundation
import Testing
@testable import PoliVerse

/// What the agenda sends, read into ``AgendaEvent``.
///
/// Decoded on every load and never tested on its own: only the performance
/// suite touched it, and only to time it.
@Suite("Agenda payload", .tags(.parsing))
struct AgendaEventDTOTests {
    private func event(_ json: String) throws -> AgendaEvent? {
        try JSONDecoder().decode(AgendaEventDTO.self, from: Data(json.utf8)).toEvent()
    }

    /// Every kind the agenda numbers, and what an unknown number becomes.
    @Test("The type id picks the kind", arguments: [
        (1, EventKind.lecture), (2, .exam), (3, .news), (4, .deadline), (5, .custom), (99, .custom),
    ])
    func kind(typeID: Int, expected: EventKind) throws {
        let parsed = try #require(try event("""
            {"event_id": 1, "date_start": "2026-03-10T09:15:00", "date_end": "2026-03-10T11:15:00",
             "event_type": {"typeId": \(typeID)}}
            """))
        #expect(parsed.kind == expected)
    }

    /// Only the timestamps are load-bearing: an entry that cannot be placed in
    /// time would sit on a guessed day.
    @Test("An entry without usable timestamps is dropped", arguments: [
        #"{"event_id": 1, "date_end": "2026-03-10T11:15:00"}"#,
        #"{"event_id": 1, "date_start": "2026-03-10T09:15:00"}"#,
        #"{"event_id": 1, "date_start": "ieri", "date_end": "2026-03-10T11:15:00"}"#,
        #"{"event_id": 1, "date_start": "2026-03-10T09:15:00", "date_end": ""}"#,
    ])
    func unplaceable(json: String) throws {
        #expect(try event(json) == nil)
    }

    @Test("Missing text degrades to defaults rather than dropping the entry")
    func defaults() throws {
        let parsed = try #require(try event("""
            {"event_id": 7, "date_start": "2026-03-10T09:15:00", "date_end": "2026-03-10T11:15:00",
             "title": {"it": ""}, "description": {"it": ""},
             "tags": [{"denomination": {"it": ""}}, {"denomination": {"it": "Laboratorio"}}]}
            """))
        #expect(parsed.title == "Evento")
        #expect(parsed.details == nil)
        #expect(parsed.kind == .custom)
        #expect(parsed.tags == ["Laboratorio"])
    }

    /// Seeded per process, `hashValue` gave an id-less entry a new id on every
    /// launch. The value is pinned so a change to the hash is a decision.
    @Test("An entry without an id gets the same one on every launch")
    func fallbackIDIsStable() throws {
        let parsed = try #require(try event("""
            {"date_start": "2026-03-10T09:15:00", "date_end": "2026-03-10T11:15:00",
             "title": {"it": "Analisi 1"}}
            """))
        #expect(parsed.id == 5_450_459_869_067_247_258)
    }

    /// The load keeps one entry per id, so two id-less entries at the same
    /// moment used to become one.
    @Test("Two entries without ids at the same moment stay two")
    func fallbackIDsDiffer() throws {
        let first = try #require(try event("""
            {"date_start": "2026-03-10T09:15:00", "date_end": "2026-03-10T11:15:00", "title": {"it": "Analisi 1"}}
            """))
        let second = try #require(try event("""
            {"date_start": "2026-03-10T09:15:00", "date_end": "2026-03-10T11:15:00", "title": {"it": "Fisica"}}
            """))
        #expect(first.id != second.id)
        #expect(first.id > Int(Int32.max))
    }

    /// Rome wall clock either side of both 2026 changes: the hour a lecture
    /// starts must not move with daylight saving.
    @Test("Wall-clock hours survive daylight saving", arguments: [
        "2026-03-28T09:15:00", "2026-03-30T09:15:00", "2026-10-24T09:15:00", "2026-10-26T09:15:00",
    ])
    func daylightSaving(start: String) throws {
        let parsed = try #require(try event("""
            {"event_id": 1, "date_start": "\(start)", "date_end": "\(start)"}
            """))
        let parts = PoliMiDate.romeCalendar.dateComponents([.hour, .minute], from: parsed.start)
        #expect(parts.hour == 9)
        #expect(parts.minute == 15)
    }
}
