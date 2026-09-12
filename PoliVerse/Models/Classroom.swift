import Foundation

/// A teaching room.
///
/// Joined from the maps service's three catalogues — rooms, buildings and
/// campuses — which share the `csi*` codes as foreign keys:
/// a room's `csie` names its building, and a building's `csic` its campus.
nonisolated struct Classroom: Identifiable, Sendable, Hashable, Codable {
    /// The code printed on the door, e.g. `"MI.B2.1"`.
    let id: String
    let capacity: Int
    /// Building code (`csie`).
    let buildingCode: String
    /// Floor code (`csip`).
    let floorCode: String
    var buildingName: String?
    var floorName: String?
    var campusName: String?
    var address: String?
    /// Seats reserved for wheelchair users, where the catalogue records any.
    var accessibleSeats: Int?
    /// `idaula` — the key the occupancy endpoint takes.
    ///
    /// Distinct from ``id``, which is the room's printed code (`2.0.1`).
    /// `/ricerca/aula/occupazione` accepts only this numeric id; passing the
    /// code or the `csiv` answers 500 or 404.
    var occupancyID: String?
    /// `csiv` — the room's own space code, which the floor-plan endpoint uses
    /// to highlight it. Different again from ``id`` and ``occupancyID``: this
    /// catalogue keys the same room three ways.
    var roomCode: String?

    /// The city or campus a room sits in, for grouping.
    var locationLabel: String {
        [campusName, buildingName].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Wire types

nonisolated struct ClassroomDTO: Decodable, Sendable {
    let sigla: String?
    let csie: String?
    let csip: String?
    let csiv: String?
    let idaula: String?
    let capienza: String?
    let posti_disabili: String?
    let categoria: String?
    let tipologia: String?

    /// Rooms the catalogue marks as fictitious or out of service are still in
    /// the payload; a room with no code or no seats is not somewhere anyone can
    /// be sent.
    func toClassroom() -> Classroom? {
        guard
            let sigla, !sigla.isEmpty,
            let csie, let csip,
            let seats = capienza.flatMap(Int.init), seats > 0
        else { return nil }

        return Classroom(
            id: sigla,
            capacity: seats,
            buildingCode: csie,
            floorCode: csip,
            accessibleSeats: posti_disabili.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil },
            occupancyID: idaula,
            roomCode: csiv
        )
    }
}

nonisolated struct BuildingDTO: Decodable, Sendable {
    let csie: String?
    let csic: String?
    let nome: String?
    let indirizzo: String?
    let prefissoToponomastico: String?
    let numeroCivico: String?
    let cittaEdificio: String?
    let visibile: String?

    /// "Via Colombo 40, Milano" from the pieces the catalogue keeps apart.
    var fullAddress: String? {
        let street = [prefissoToponomastico, indirizzo, numeroCivico]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, cittaEdificio].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

nonisolated struct CampusDTO: Decodable, Sendable {
    let csic: String?
    let csis: String?
    let nome: String?
    let visibile: String?
}

nonisolated struct FloorDTO: Decodable, Sendable {
    let csip: String?
    let csie: String?
    let nome: String?
}

nonisolated extension Classroom {
    /// The official floor plan, with this room highlighted where the catalogue
    /// knows its space code.
    ///
    /// `GET /download/img/piano/{csip}` is the plain floor; adding `{csiv}`
    /// returns the same drawing with one room filled in. Public, no token, and
    /// the only room-accurate picture of the building that exists — the
    /// geojson has no real footprints to draw instead.
    var floorPlanURL: URL? {
        guard !floorCode.isEmpty else { return nil }
        var url = URL(string: "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano")!
        url.append(path: floorCode)
        if let roomCode, !roomCode.isEmpty { url.append(path: roomCode) }
        return url
    }
}
