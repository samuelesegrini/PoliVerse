import Foundation

/// A teaching room.
///
/// Joined from the maps service's three catalogues — rooms, buildings and campuses —
/// which share the `csi*` codes as foreign keys: a room's `csie` names its building
/// and a building's `csic` its campus.
///
/// The catalogue keys the same room three ways, and the three are not
/// interchangeable: ``id`` is the code on the door, ``occupancyID`` is what the
/// bookings endpoint takes, and ``roomCode`` is what the floor-plan endpoint
/// highlights by.
nonisolated struct Classroom: Identifiable, Sendable, Hashable, Codable {
    /// The code printed on the door, for example `"MI.B2.1"`.
    let id: String
    /// How many seats the room has.
    let capacity: Int
    /// The building's code, `csie`, which also keys ``BuildingLocation``.
    let buildingCode: String
    /// The floor's code, `csip`, which the floor-plan endpoint takes.
    let floorCode: String
    /// The building's name, once the building catalogue is joined in.
    var buildingName: String?
    /// The floor's name, where the catalogue records one.
    var floorName: String?
    /// The campus's name, once the campus catalogue is joined in.
    var campusName: String?
    /// The building's street address, where recorded.
    var address: String?
    /// Seats reserved for wheelchair users, where the catalogue records any.
    var accessibleSeats: Int?
    /// The `idaula` the bookings endpoint takes.
    ///
    /// Distinct from ``id``: `/ricerca/aula/occupazione` accepts only this numeric id, and
    /// answers 500 or 404 for the printed code or the space code.
    var occupancyID: String?
    /// The room's own space code, `csiv`, which the floor-plan endpoint uses to highlight
    /// it. See ``floorPlanURL``.
    var roomCode: String?

    /// The campus and building as one line, joined by a middle dot. Empty when neither is
    /// known.
    var locationLabel: String {
        [campusName, buildingName].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Wire types

/// The room's floor plan.
nonisolated extension Classroom {
    /// The official floor plan, with this room filled in where ``roomCode`` is known.
    ///
    /// `GET /download/img/piano/{csip}` is the plain floor; appending the space code
    /// returns the same drawing with one room highlighted. Public and needing no token,
    /// and the only room-accurate picture of a building that exists — the geojson carries
    /// no real footprints to draw instead.
    ///
    /// `nil` when the room has no floor code.
    var floorPlanURL: URL? {
        guard !floorCode.isEmpty else { return nil }
        var url = URL(string: "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano")!
        url.append(path: floorCode)
        if let roomCode, !roomCode.isEmpty { url.append(path: roomCode) }
        return url
    }
}
