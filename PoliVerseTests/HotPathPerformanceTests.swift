import XCTest
@testable import PoliVerse

/// Timings for the pure functions every load runs through, at the sizes a
/// real payload reaches.
///
/// XCTest rather than Swift Testing, which has no `measure`. Kept in the unit
/// target because none of this needs the UI: a parser that gets slower shows
/// up here in seconds, long before it shows up as a hitch. The numbers come
/// from a Debug build and a shared simulator, so they are for comparing a
/// change with its parent, not for quoting — set a baseline in Xcode's report
/// to have a regression fail the run (`docs/metrickit-performance.md`, Phase 3).
nonisolated final class HotPathPerformanceTests: XCTestCase {
    /// A month of a busy timetable, as the agenda endpoint sends it.
    private static let agendaPayload: Data = {
        let events = (0..<600).map { index in
            let day = 1 + index % 28
            let hour = 8 + index % 10
            return """
            {"event_id":\(index),"date_start":"2026-10-\(String(format: "%02d", day))T\(String(format: "%02d", hour)):15:00",\
            "date_end":"2026-10-\(String(format: "%02d", day))T\(String(format: "%02d", hour + 1)):45:00",\
            "title":{"it":"Analisi Matematica \(index % 12)","en":"Calculus"},\
            "event_type":{"typeId":1,"type_dn":{"it":"Lezione","en":"Lecture"}},\
            "room":{"room_dn":"Aula \(index % 40)","acronym_dn":"B.\(index % 9).\(index % 7)"},\
            "calendar":{"calendar_dn":{"it":"Lezioni","en":"Lectures"}},\
            "tags":[{"event_tag_id":3,"denomination":{"it":"Obbligatoria"}}]}
            """
        }
        return Data("[\(events.joined(separator: ","))]".utf8)
    }()

    /// A Manifesti teaching page is a long run of these cards.
    private static let manifestoPage: String = {
        let card = """
        <TABLE class="BoxInfoCard">
        <tr><td class="ElementInfoCard1 jaf-card-element"> Anno Accademico </td>
            <td class="ElementInfoCard2 jaf-card-element"> 2026/2027 </td></tr>
        <tr><td class="ElementInfoCard1"> Programma sintetico </td>
            <td class="ElementInfoCard2"> Scopo di questo corso &egrave; introdurre gli strumenti &#8220;matematici&#8221;. </td></tr>
        </TABLE>
        """
        return String(repeating: card, count: 150)
            + #"<TABLE class="BoxInfoCard"><tr><td class="ElementInfoCard1"> Codice Identificativo </td><td class="ElementInfoCard2"> 086214 </td></tr></TABLE>"#
    }()

    private static let newsHTML = String(
        repeating: "<p>La scadenza &egrave; il <b>15 ottobre</b>.<br/>Universit&agrave; &#8211; iscrizioni</p><ul><li>Uno</li><li>Due</li></ul>",
        count: 200)

    func testAgendaDecodeAndConvert() throws {
        let data = Self.agendaPayload
        measure {
            let dtos = try? JSONDecoder().decode([AgendaEventDTO].self, from: data)
            XCTAssertEqual(dtos?.compactMap { $0.toEvent() }.count, 600)
        }
    }

    func testAgendaDayIndex() {
        let events = (try? JSONDecoder().decode([AgendaEventDTO].self, from: Self.agendaPayload))?
            .compactMap { $0.toEvent() } ?? []
        measure {
            XCTAssertEqual(AgendaService.index(events).count, 28)
        }
    }

    func testManifestoCardLookup() {
        let page = Self.manifestoPage
        measure {
            for _ in 0..<20 {
                XCTAssertEqual(HTMLScraper.cardValue("Codice Identificativo", in: page), "086214")
            }
        }
    }

    func testNewsHTMLToText() {
        let html = Self.newsHTML
        measure {
            for _ in 0..<10 {
                XCTAssertFalse(HTMLText.plain(html).isEmpty)
            }
        }
    }

    func testNoticeDateParsing() {
        let values: [JSONValue] = (0..<2_000).map { index in
            .string(index.isMultiple(of: 2) ? "2026-10-15T08:30:00Z" : "2026-10-15T08:30:00.250Z")
        }
        measure {
            XCTAssertEqual(values.compactMap(Notice.date(from:)).count, 2_000)
        }
    }
}
