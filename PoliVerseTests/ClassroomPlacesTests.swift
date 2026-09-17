import Foundation
import Testing
@testable import PoliVerse

/// Where a room is, and how it is drawn.
///
/// The catalogue keys the same room three ways — the code on the door, the
/// `idaula` the occupancy endpoint takes, and the `csiv` the floor plan
/// highlights — and passing one where another is expected answers 404 or 500
/// rather than saying so. Decoding the catalogue is pinned in `ModelTests`;
/// this is what the app does with a room once it has one.
@Suite("Dove sta un’aula")
struct ClassroomPlacesTests {
    private func room(floor: String = "45", code: String? = "9001") -> Classroom {
        Classroom(id: "2.0.1", capacity: 120, buildingCode: "12", floorCode: floor,
                  occupancyID: "46", roomCode: code)
    }

    /// The three keys are three different things, and stay that way.
    @Test("Le tre chiavi di un’aula restano distinte")
    func threeKeys() {
        let room = room()
        #expect(room.id == "2.0.1", "L’identificativo è il codice sulla porta")
        #expect(room.occupancyID == "46", "L’occupazione vuole l’idaula")
        #expect(room.roomCode == "9001", "La pianta vuole il csiv")
    }

    @Test("Il luogo unisce campus ed edificio, e salta quello che manca")
    func locationLabel() {
        var room = room()
        #expect(room.locationLabel == "")

        room.campusName = "Milano Leonardo"
        #expect(room.locationLabel == "Milano Leonardo")

        room.buildingName = "Edificio 2"
        #expect(room.locationLabel == "Milano Leonardo · Edificio 2")

        room.campusName = nil
        #expect(room.locationLabel == "Edificio 2", "Un pezzo mancante non lascia un separatore penzolante")
    }

    /// `…/piano/{csip}` is the plain floor; adding the `csiv` returns the same
    /// drawing with this room filled in.
    @Test("La pianta punta al piano, e all’aula quando la si conosce")
    func floorPlan() throws {
        #expect(try #require(room().floorPlanURL).absoluteString
                == "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano/45/9001")
        #expect(try #require(room(code: nil).floorPlanURL).absoluteString
                == "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano/45")
        #expect(try #require(room(code: "").floorPlanURL).absoluteString.hasSuffix("/piano/45"),
                "Un csiv vuoto non deve finire nell’indirizzo")
    }

    /// The floor is the whole address of the drawing; without it there is no
    /// picture to ask for.
    @Test("Senza piano non c’è pianta da mostrare")
    func noFloorPlan() {
        #expect(room(floor: "").floorPlanURL == nil)
    }
}
