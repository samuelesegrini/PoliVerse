import Foundation
import Observation
import OSLog

/// The room catalogue, from the Politecnico's maps service.
///
/// ## On "aule libere"
///
/// Live occupancy is **not available** to this app, and the catalogue is what
/// remains. Every source that knows which rooms are busy is out of reach:
///
/// - `www7.ceda.polimi.it`, `www11.ceda.polimi.it` and `aule.polimi.it` all
///   resolve but refuse connections from the public internet — campus-internal,
///   the same way `www22.dmz.polimi.it` was.
/// - PoliNetwork's `/v1/rooms/search`, which PoliFemo uses, now sits behind
///   Cloudflare Access and redirects any request to a sign-in page.
/// - The maps service exposes no occupancy endpoint; `/spazi/impegni`,
///   `/spazi/prenotazioni` and `/spazi/occupazione` all return 500.
/// - The agenda knows only *this student's* lectures, not what every room is
///   doing.
///
/// Showing a room as free without a source for that would be worse than not
/// showing it, so the app says plainly that it cannot tell. If the internal
/// hosts turn out to answer on campus Wi-Fi, that is the thread to pull.
///
/// The catalogue itself is public and needs no token.
@Observable
final class RoomsService {
    private(set) var rooms: [Classroom] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Live occupancy is unavailable; see the note above.
    let knowsOccupancy = false

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "rooms")
    private let session: URLSession
    private let base = URL(string: "https://onlineservices.polimi.it/maps_rest/rest")!

    init(session: URLSession = .shared) {
        self.session = session
        if let cached = DiskCache.load([Classroom].self, as: "rooms") {
            rooms = cached.value
        }
    }

    /// Campuses present in the catalogue, for filtering.
    var campuses: [String] {
        Array(Set(rooms.compactMap(\.campusName))).sorted()
    }

    func rooms(matching query: String, campus: String?) -> [Classroom] {
        rooms.filter { room in
            if let campus, room.campusName != campus { return false }
            guard !query.isEmpty else { return true }
            return room.id.localizedCaseInsensitiveContains(query)
                || (room.buildingName ?? "").localizedCaseInsensitiveContains(query)
                || (room.campusName ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    /// The catalogue changes rarely, so a cached copy is served immediately and
    /// only refreshed when it is missing or a refresh is asked for.
    func load(force: Bool = false) async {
        guard !isLoading, force || rooms.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Three independent catalogues; fetch together and join locally.
            async let roomsTask = fetch("/spazi/aula", as: [ClassroomDTO].self)
            async let buildingsTask = fetch("/spazi/edificio", as: [BuildingDTO].self)
            async let campusesTask = fetch("/spazi/campus", as: [CampusDTO].self)
            async let floorsTask = fetch("/spazi/piano", as: [FloorDTO].self)

            let (rawRooms, rawBuildings, rawCampuses, rawFloors) =
                try await (roomsTask, buildingsTask, campusesTask, floorsTask)

            let buildings = Dictionary(
                rawBuildings.compactMap { dto -> (String, BuildingDTO)? in
                    dto.csie.map { ($0, dto) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            let campusNames = Dictionary(
                rawCampuses.compactMap { dto -> (String, String)? in
                    guard let csic = dto.csic, let nome = dto.nome else { return nil }
                    return (csic, nome)
                },
                uniquingKeysWith: { first, _ in first }
            )
            let floorNames = Dictionary(
                rawFloors.compactMap { dto -> (String, String)? in
                    guard let csip = dto.csip, let nome = dto.nome else { return nil }
                    return (csip, nome)
                },
                uniquingKeysWith: { first, _ in first }
            )

            let joined = rawRooms.compactMap { $0.toClassroom() }.map { room -> Classroom in
                var copy = room
                let building = buildings[room.buildingCode]
                copy.buildingName = building?.nome
                copy.address = building?.fullAddress
                copy.campusName = building?.csic.flatMap { campusNames[$0] }
                copy.floorName = floorNames[room.floorCode]
                return copy
            }.sorted { $0.id < $1.id }

            log.notice("rooms: \(rawRooms.count, privacy: .public) in catalogue, \(joined.count, privacy: .public) usable")
            rooms = joined
            DiskCache.save(joined, as: "rooms")
        } catch {
            log.error("Room catalogue failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func fetch<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1, body: "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
