import Foundation
import Testing
@testable import PoliVerse

/// Rooms as the maps service sends them, and as the app has to read them.
///
/// The catalogue keys the same room three ways — the code on the door, the
/// `idaula` the occupancy endpoint takes, and the `csiv` the floor plan
/// highlights — and mixing them up answers 404 or 500 rather than saying so.
/// It also ships rooms that are fictitious or out of service, which must not
/// become somewhere a student is sent.
@Suite("Aule")
struct ClassroomTests {
    private func dto(
        sigla: String? = "2.0.1", csie: String? = "12", csip: String? = "45",
        csiv: String? = "9001", idaula: String? = "46", capienza: String? = "120",
        posti: String? = nil
    ) -> ClassroomDTO {
        ClassroomDTO(sigla: sigla, csie: csie, csip: csip, csiv: csiv, idaula: idaula,
                     capienza: capienza, posti_disabili: posti, categoria: nil, tipologia: nil)
    }

    @Test("Una riga completa diventa un’aula, con le sue tre chiavi distinte")
    func complete() throws {
        let room = try #require(dto().toClassroom())

        #expect(room.id == "2.0.1", "L’identificativo è il codice sulla porta")
        #expect(room.occupancyID == "46", "L’occupazione vuole l’idaula")
        #expect(room.roomCode == "9001", "La pianta vuole il csiv")
        #expect(room.capacity == 120)
        #expect(room.buildingCode == "12")
        #expect(room.floorCode == "45")
    }

    /// A room with no code on the door is not somewhere anyone can be sent.
    @Test("Una riga senza codice non diventa un’aula")
    func withoutACode() {
        #expect(dto(sigla: nil).toClassroom() == nil)
        #expect(dto(sigla: "").toClassroom() == nil)
    }

    /// Zero seats is how the catalogue marks the fictitious and the retired.
    @Test("Una riga senza posti non diventa un’aula")
    func withoutSeats() {
        #expect(dto(capienza: nil).toClassroom() == nil)
        #expect(dto(capienza: "0").toClassroom() == nil)
        #expect(dto(capienza: "non un numero").toClassroom() == nil)
    }

    @Test("Senza edificio o piano non si può collocare")
    func withoutAPlace() {
        #expect(dto(csie: nil).toClassroom() == nil)
        #expect(dto(csip: nil).toClassroom() == nil)
    }

    /// Reported only where the catalogue records any: a zero here means "not
    /// recorded", and showing "0 posti accessibili" would read as a promise
    /// the catalogue never made.
    @Test("I posti accessibili ci sono solo quando il catalogo ne registra")
    func accessibleSeats() throws {
        #expect(try #require(dto(posti: "4").toClassroom()).accessibleSeats == 4)
        #expect(try #require(dto(posti: "0").toClassroom()).accessibleSeats == nil)
        #expect(try #require(dto(posti: nil).toClassroom()).accessibleSeats == nil)
    }

    // MARK: Come si legge

    @Test("Il luogo unisce campus ed edificio, e salta quello che manca")
    func locationLabel() {
        var room = Classroom(id: "2.0.1", capacity: 120, buildingCode: "12", floorCode: "45")
        #expect(room.locationLabel == "")

        room.campusName = "Milano Leonardo"
        #expect(room.locationLabel == "Milano Leonardo")

        room.buildingName = "Edificio 2"
        #expect(room.locationLabel == "Milano Leonardo · Edificio 2")
    }

    // MARK: La pianta

    /// `…/piano/{csip}` is the plain floor; adding the `csiv` returns the same
    /// drawing with this room filled in.
    @Test("La pianta punta al piano, e all’aula quando la si conosce")
    func floorPlan() throws {
        var room = Classroom(id: "2.0.1", capacity: 120, buildingCode: "12", floorCode: "45",
                             roomCode: "9001")
        #expect(try #require(room.floorPlanURL).absoluteString
                == "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano/45/9001")

        room.roomCode = nil
        #expect(try #require(room.floorPlanURL).absoluteString
                == "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano/45")

        room.roomCode = ""
        #expect(try #require(room.floorPlanURL).absoluteString.hasSuffix("/piano/45"),
                "Un csiv vuoto non deve finire nell’indirizzo")
    }

    @Test("Senza piano non c’è pianta da mostrare")
    func noFloorPlan() {
        let room = Classroom(id: "2.0.1", capacity: 120, buildingCode: "12", floorCode: "")
        #expect(room.floorPlanURL == nil)
    }

    // MARK: Gli edifici

    @Test("L’indirizzo si ricompone dai pezzi che il catalogo tiene separati")
    func fullAddress() {
        #expect(building(prefix: "Via", street: "Colombo", number: "40", city: "Milano")
                .fullAddress == "Via Colombo 40, Milano")
        #expect(building(prefix: nil, street: "Piazza Leonardo da Vinci", number: "32", city: nil)
                .fullAddress == "Piazza Leonardo da Vinci 32")
        #expect(building(prefix: "", street: "Colombo", number: "", city: "Milano")
                .fullAddress == "Colombo, Milano", "I pezzi vuoti non lasciano spazi doppi")
    }

    @Test("Un edificio senza indirizzo non ne inventa uno")
    func noAddress() {
        #expect(building(prefix: nil, street: nil, number: nil, city: nil).fullAddress == nil)
    }

    private func building(prefix: String?, street: String?, number: String?, city: String?) -> BuildingDTO {
        BuildingDTO(csie: "12", csic: "1", nome: "Edificio 2", indirizzo: street,
                    prefissoToponomastico: prefix, numeroCivico: number,
                    cittaEdificio: city, visibile: "1")
    }
}
