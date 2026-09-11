import Foundation
import Testing
@testable import PoliVerse

/// `/ricerca/aula/dotazioni/{idaula}` and `/ricerca/aula/software/{idaula}`,
/// both public and both shaped `[{"id":Int,"it":String,"en":String}]`.
/// The bodies below are verbatim from real rooms.
@Suite("Room facilities")
struct RoomFacilityTests {
    private func facilities(_ json: String) -> [RoomFacility] {
        (try? JSONDecoder().decode([RoomFacility].self, from: Data(json.utf8))) ?? []
    }

    @Test("A real dotazioni payload decodes, preferring Italian")
    func equipment() {
        let parsed = facilities("""
        [{"id":4,"it":"Video proiettore","en":"Video projector"},
         {"id":142,"it":"Postazioni dotate di presa elettrica","en":"Seats with electric socket"}]
        """)
        #expect(parsed.count == 2)
        #expect(parsed[0].name == "Video proiettore")
        #expect(parsed[1].name == "Postazioni dotate di presa elettrica")
    }

    @Test("A real software payload decodes")
    func software() {
        let parsed = facilities("""
        [{"id":257,"it":"MICROSOFT Edge (Chromium based)","en":"MICROSOFT Edge (Chromium based)"},
         {"id":348,"it":"Overleaf","en":"Overleaf"}]
        """)
        #expect(parsed.map(\.name) == ["MICROSOFT Edge (Chromium based)", "Overleaf"])
    }

    /// Most rooms return `[]`, and software only the computer labs. That is an
    /// answer, not a failure.
    @Test("An empty list decodes as empty rather than failing")
    func emptyIsValid() {
        #expect(facilities("[]").isEmpty)
    }

    @Test("An entry with only English still shows")
    func englishOnly() {
        let parsed = facilities("""
        [{"id":1,"it":null,"en":"Whiteboard"}]
        """)
        #expect(parsed.first?.name == "Whiteboard")
    }

    @Test("Symbols are matched on wording, with a neutral fallback")
    func symbols() {
        #expect(facilities("""
        [{"id":4,"it":"Video proiettore","en":null}]
        """).first?.symbol == "videoprojector")
        #expect(facilities("""
        [{"id":5,"it":"Radio microfono","en":null}]
        """).first?.symbol == "mic")
        #expect(facilities("""
        [{"id":9,"it":"Qualcosa di ignoto","en":null}]
        """).first?.symbol == "checkmark.circle")
    }

    /// `idaula` is what both endpoints take — the same key as occupancy, and
    /// not the printed room code.
    @Test("The catalogue carries idaula through to the room")
    func catalogueCarriesID() {
        let json = """
        [{"sigla":"2.0.1","csie":"MIA0102","csip":"MIA0102000","capienza":"307","idaula":"32"}]
        """
        let rooms = (try? JSONDecoder().decode([ClassroomDTO].self, from: Data(json.utf8)))?
            .compactMap { $0.toClassroom() } ?? []
        #expect(rooms.count == 1)
        #expect(rooms[0].id == "2.0.1")
        #expect(rooms[0].occupancyID == "32")
    }
}
