import Foundation
import Testing
@testable import PoliVerse

/// `/v1/persona/news` sits on the agenda host beside `/events`, whose shape is
/// known, so the agenda's field names lead the candidate lists. The body
/// itself is still unconfirmed, so these pin the same guarantee as the
/// notifications suite: a wrong guess costs a field, never the list.
@Suite("News")
struct NewsTests {
    private func items(_ json: String) -> [NewsItem] {
        (try? JSONDecoder().decode(NewsResponse.self, from: Data(json.utf8)))?.items ?? []
    }

    /// The shape the agenda already uses for events, which is the most likely
    /// answer for news on the same service.
    @Test("Agenda-shaped rows decode, localised title included")
    func agendaShape() {
        let parsed = items("""
        [{"news_id": 91, "title": {"it": "Bandi di mobilità", "en": "Mobility"},
          "description": {"it": "Candidature entro il 15 febbraio.", "en": "Apply by 15 February."},
          "date_start": "2026-02-01T09:00:00", "date_end": "2027-02-15T23:59:00"}]
        """)
        #expect(parsed.count == 1)
        #expect(parsed[0].title == "Bandi di mobilità")
        #expect(parsed[0].summary?.hasPrefix("Candidature") == true)
        #expect(parsed[0].published != nil)
        #expect(parsed[0].expires != nil)
    }

    @Test("A category nested under type_dn is unwrapped")
    func nestedCategory() {
        let parsed = items("""
        [{"news_id": 1, "title": "Seminario",
          "type": {"typeId": 4, "type_dn": {"it": "Eventi", "en": "Events"}}}]
        """)
        #expect(parsed[0].category == "Eventi")
    }

    @Test("A category taken from the first tag when there is no type")
    func tagCategory() {
        let parsed = items("""
        [{"news_id": 1, "title": "Seminario",
          "tags": [{"event_tag_id": 6, "denomination": {"it": "Campus"}}]}]
        """)
        #expect(parsed[0].category == "Campus")
    }

    @Test("An image given as an object is unwrapped to its URL")
    func nestedImage() {
        let parsed = items("""
        [{"news_id": 1, "title": "Con foto",
          "image": {"url": "https://www.polimi.it/a.jpg", "alt": "x"}}]
        """)
        #expect(parsed[0].imageURL?.lastPathComponent == "a.jpg")
    }

    @Test("An array behind an unguessed wrapper key is still found")
    func wrappedArray() {
        let parsed = items("""
        {"totale": 1, "ELENCO_NEWS": [{"news_id": 3, "titolo": "Una"}]}
        """)
        #expect(parsed.count == 1)
    }

    @Test("An unreadable row is dropped, not the whole list")
    func oneBadRow() {
        let parsed = items("""
        [{"news_id": 1, "title": "Buona"}, {"strano": [1, 2]}, {"news_id": 3, "title": "Anche"}]
        """)
        #expect(parsed.count == 2)
    }

    /// The guard against the decoder emptying the screen on a wrong guess:
    /// only an explicit end date in the past retires an item.
    @Test("Missing end date means current, not expired")
    func missingEndDateIsCurrent() {
        let item = NewsItem(id: "1", title: "Senza scadenza", summary: nil,
                            published: nil, expires: nil, category: nil,
                            link: nil, imageURL: nil)
        #expect(item.isCurrent())
    }

    @Test("An end date in the past retires the item")
    func pastEndDateExpires() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let item = NewsItem(id: "1", title: "Scaduta", summary: nil,
                            published: nil, expires: now.addingTimeInterval(-60),
                            category: nil, link: nil, imageURL: nil)
        #expect(!item.isCurrent(now: now))
    }
}

/// The real payload, confirmed from a device run on 2026-09-11. The first cut
/// guessed `date_start` from the agenda's events and read no date at all — all
/// forty items came back undated and therefore unsorted.
@Suite("News wire shape")
struct NewsWireShapeTests {
    private func items(_ json: String) -> [NewsItem] {
        (try? JSONDecoder().decode(NewsResponse.self, from: Data(json.utf8)))?.items ?? []
    }

    private var real: String {
        """
        [{"news_id": 4412, "news_source_id": 3,
          "title": {"it": "Seminario", "en": "Seminar"},
          "text": {"it": "<p>Aula Rogers.</p>", "en": "<p>Rogers.</p>"},
          "publication_start": "2026-09-01T00:00:00",
          "publication_end": "2026-10-01T00:00:00",
          "event_start": "2026-09-20T17:00:00",
          "event_end": "2026-09-20T19:00:00",
          "show_agenda": true,
          "tags": [{"event_tag_id": 6, "denomination": {"it": "Eventi"}}]}]
        """
    }

    @Test("Every field of the real shape is read")
    func realShape() {
        let parsed = items(real)
        #expect(parsed.count == 1)
        #expect(parsed[0].id == "4412")
        #expect(parsed[0].title == "Seminario")
        #expect(parsed[0].summary == "Aula Rogers.")
        #expect(parsed[0].published != nil)
        #expect(parsed[0].expires != nil)
        #expect(parsed[0].eventStart != nil)
        #expect(parsed[0].eventEnd != nil)
        #expect(parsed[0].category == "Eventi")
    }

    /// The two date pairs mean different things, and confusing them would
    /// retire a notice about next month's seminar the moment it went up.
    @Test("Publication and event dates are kept apart")
    func datePairsDistinct() {
        let item = items(real)[0]
        #expect(item.published != item.eventStart)
        // The event is what a reader wants to know about.
        #expect(item.displayDate == item.eventStart)
    }

    @Test("An item is retired by publication_end, not by its event date")
    func expiryUsesPublicationEnd() {
        let item = items(real)[0]
        let afterEvent = Date(timeIntervalSince1970: 1_758_400_000)   // 2025
        #expect(item.isCurrent(now: afterEvent))
    }

    @Test("A span across one day is not repeated")
    func singleDaySpan() {
        let item = items(real)[0]
        let text = NewsItem.span(from: item.eventStart!, to: item.eventEnd!)
        #expect(!text.contains("–"))
    }
}
