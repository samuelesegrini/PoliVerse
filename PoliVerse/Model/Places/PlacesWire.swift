import Foundation

// The shapes the maps service sends: rooms, buildings, campuses, floors.
//
// The catalogue keys the same room three ways and ships rows that are
// fictitious or out of service; turning those into somewhere a student can be
// sent is `toClassroom()`'s job, and it lives here with them.

/// One room as the maps service's room catalogue sends it.
///
/// The catalogue keys the same room three ways and ships rows that are fictitious or
/// out of service, which ``toClassroom()`` filters out.
nonisolated struct ClassroomDTO: Decodable, Sendable {
    /// The code printed on the door.
    let sigla: String?
    /// The building code.
    let csie: String?
    /// The floor code.
    let csip: String?
    /// The room's own space code, which the floor-plan endpoint highlights by.
    let csiv: String?
    /// The numeric id the bookings and facilities endpoints take.
    let idaula: String?
    /// Seating capacity, sent as a string.
    let capienza: String?
    /// Seats reserved for wheelchair users, sent as a string.
    let posti_disabili: String?
    /// The catalogue's own category for the room.
    let categoria: String?
    /// The catalogue's own type for the room.
    let tipologia: String?

    /// Converts the payload into a ``Classroom``.
    ///
    /// - Returns: The room, or `nil` when it has no printed code, no building, no floor
    ///   or no seats — none of which describes somewhere a student can be sent. Zero
    ///   accessible seats become `nil` rather than zero.
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

/// One building as the maps service's building catalogue sends it.
nonisolated struct BuildingDTO: Decodable, Sendable {
    /// The building code, which rooms refer to.
    let csie: String?
    /// The campus code this building belongs to.
    let csic: String?
    /// The building's name.
    let nome: String?
    /// The street name, without prefix or number.
    let indirizzo: String?
    /// The street's prefix, for example “Via” or “Piazza”.
    let prefissoToponomastico: String?
    /// The street number.
    let numeroCivico: String?
    /// The city the building is in.
    let cittaEdificio: String?
    /// Whether the catalogue publishes this building.
    let visibile: String?

    /// The address as one line, assembled from the pieces the catalogue keeps apart —
    /// for example `"Via Colombo 40, Milano"`.
    ///
    /// `nil` when neither a street nor a city is recorded.
    var fullAddress: String? {
        let street = [prefissoToponomastico, indirizzo, numeroCivico]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " ")
        let parts = [street.isEmpty ? nil : street, cittaEdificio].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// One site as the maps service's site catalogue sends it: a city, or a campus
/// within Milan, grouping several addresses.
nonisolated struct SiteDTO: Decodable, Sendable {
    /// The site code, which campuses refer to.
    let csis: String?
    /// The site's name, for example "Milano Bovisa" or "Como".
    let nome: String?
    /// Whether the catalogue publishes this site.
    let visibile: String?
}

/// One campus as the maps service's campus catalogue sends it.
nonisolated struct CampusDTO: Decodable, Sendable {
    /// The campus code, which buildings refer to.
    let csic: String?
    /// The site code the campus belongs to.
    let csis: String?
    /// The campus's name.
    let nome: String?
    /// Whether the catalogue publishes this campus.
    let visibile: String?
}

/// One floor as the maps service's floor catalogue sends it.
nonisolated struct FloorDTO: Decodable, Sendable {
    /// The floor code, which rooms refer to.
    let csip: String?
    /// The building this floor is in.
    let csie: String?
    /// The floor's name.
    let nome: String?
}
