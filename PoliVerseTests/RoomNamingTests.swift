import Foundation
import Testing
@testable import PoliVerse

/// Which of a room's two names to show.
///
/// The timetable writes a hall's name and the ateneo's internal code into the
/// same field, and nothing in the payload says which arrived. Everything here
/// is about that one distinction, because getting it wrong either hides a name
/// everybody uses — Rogers, De Donato — or shows `"005A"`, which is printed on
/// no door.
@Suite("Room naming")
struct RoomNamingTests {
    private func event(room: String?, code: String?) -> AgendaEvent {
        let start = Date(timeIntervalSince1970: 1_772_000_000)
        return AgendaEvent(id: 1, title: "Analisi", start: start,
                           end: start.addingTimeInterval(7200), kind: .lecture,
                           room: room, roomAcronym: code)
    }

    @Test("Halls are named after people and places", arguments: [
        "Aula Rogers", "Aula De Donato", "Aula Magna", "Laboratorio Informatico", "Teatro",
    ])
    func names(_ room: String) {
        #expect(RoomNaming.isName(room))
    }

    /// `"Aula 3"` is a number with a word in front of it, not a name — the
    /// door code says more.
    @Test("Codes are numbered, whatever word is in front of them", arguments: [
        "005A", "5.1.1", "Aula 3", "B2.1", "L.26",
    ])
    func codes(_ room: String) {
        #expect(!RoomNaming.isName(room))
    }

    @Test("A named hall is shown by name, with the door code beside it")
    func namedHall() {
        let lecture = event(room: "Aula Rogers", code: "R.0.1")
        #expect(lecture.roomLabel == "Aula Rogers")
        #expect(lecture.roomCode == "R.0.1")
    }

    /// The whole point: `"005A"` never reaches a student.
    @Test("An internal code is replaced by the door code, not shown beside it")
    func internalCode() {
        let lecture = event(room: "005A", code: "5.1.1")
        #expect(lecture.roomLabel == "5.1.1")
        #expect(lecture.roomCode == nil)
    }

    /// Nothing better to offer, so the internal code stands rather than the
    /// student being told nothing at all.
    @Test("With no door code the internal code is all there is")
    func noDoorCode() {
        #expect(event(room: "005A", code: nil).roomLabel == "005A")
    }

    @Test("A room with neither has no label")
    func neither() {
        #expect(event(room: nil, code: nil).roomLabel == nil)
    }

    @Test("The word is added to a bare code and not to a name")
    func sentences() {
        #expect(RoomNaming.sentence("5.1.1") == "Aula 5.1.1")
        #expect(RoomNaming.sentence("Aula Rogers") == "Aula Rogers")
        #expect(RoomNaming.sentence("Laboratorio Informatico") == "Laboratorio Informatico")
    }

    /// Under a heading that already says "Aula", the value gives up its copy.
    @Test("The word is taken off for a field already labelled with it")
    func bareValues() {
        #expect(RoomNaming.bare("Aula Magna") == "Magna")
        #expect(RoomNaming.bare("Aula Rogers") == "Rogers")
        #expect(RoomNaming.bare("5.1.1") == "5.1.1")
        #expect(RoomNaming.bare("005A") == "005A")
    }

    /// Stripping a label that is nothing but the word would leave an empty
    /// row, so the word stays.
    @Test("A label that is only the word keeps it")
    func bareKeepsLoneWord() {
        #expect(RoomNaming.bare("Aula") == "Aula")
        #expect(RoomNaming.bare("Teatro") == "Teatro")
    }

    /// The two wordings are opposites and have to stay so: whatever
    /// ``RoomNaming/sentence(_:)`` says can be handed to
    /// ``RoomNaming/bare(_:)`` and come back to where it started.
    @Test("Wording a room and unwording it round-trips", arguments: [
        "5.1.1", "005A", "Aula Rogers", "Aula Magna", "B.3.2",
    ])
    func roundTrip(_ room: String) {
        #expect(RoomNaming.bare(RoomNaming.sentence(room)) == RoomNaming.bare(room))
    }
}
