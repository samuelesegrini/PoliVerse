import Foundation
import Observation
import OSLog

/// The room catalogue, from the Politecnico's maps service.
///
/// ## On "aule libere"
///
/// Occupancy **is** available, and lives in ``FreeRoomsService``. This type
/// stays the catalogue: every room on campus with its building, floor and
/// capacity, public and needing no token.
///
/// The distinction is worth keeping. The catalogue answers "where is room
/// 3.0.1"; the bookings service answers "what is happening in it". They come
/// from different backends — `maps_rest` and `ws_aule` — with different auth
/// and different lifetimes, and joining them into one type would tie the
/// catalogue's availability to a token it does not need.
///
/// An earlier version of this comment asserted that occupancy was
/// unreachable, having checked the CEDA hosts, PoliNetwork and `maps_rest`.
/// All of those findings still hold; the conclusion drawn from them did not,
/// because `props` lists a `ws_aule` service that was never probed. It answers
/// 401, not 404.
///
/// The catalogue itself is public and needs no token.
@Observable
final class RoomsService {
    private(set) var rooms: [Classroom] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "rooms")
    private let session: URLSession
    private let base = URL(string: "https://onlineservices.polimi.it/maps_rest/rest")!

    /// Seeds the catalogue and stops it fetching. For previews only — the
    /// maps service is unauthenticated and has no mock path of its own, so
    /// without this every preview of a room screen would hit the network.
    convenience init(preview rooms: [Classroom]) {
        self.init()
        self.rooms = rooms
        self.skipsLoading = true
    }

    private var skipsLoading = false

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
        guard !skipsLoading else { return }
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
            errorMessage = userFacingMessage(error)
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
