import Foundation

/// The shapes the maps service sends: rooms, buildings, campuses, floors.
///
/// The catalogue keys the same room three ways and ships rows that are
/// fictitious or out of service; turning those into somewhere a student can be
/// sent is `toClassroom()`'s job, and it lives here with them.

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
