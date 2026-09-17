import Foundation
import Observation
import OSLog

/// The room catalogue, from the Politecnico's maps service.
///
/// ## On "aule libere"
///
/// Occupancy **is** available, and lives in ``FreeRoomsModel``. This type
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
final class RoomsModel {
    private(set) var rooms: [Classroom] = []
    /// Campuses present in the catalogue, for filtering.
    ///
    /// Kept as a value rather than computed: it was read from view bodies —
    /// the map's campus picker among them — and a `Set` over 350 rooms on
    /// every re-render is work the main thread does not need to repeat.
    private(set) var campuses: [String] = []
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
        self.campuses = Array(Set(rooms.compactMap(\.campusName))).sorted()
        self.skipsLoading = true
    }

    private var skipsLoading = false

    init(session: URLSession = .shared) {
        self.session = session
        // The cached catalogue is *not* read here: this runs while the app is
        // launching, and decoding 350 rooms from disk on the main thread is a
        // stall before anything is on screen. ``load(force:)`` reads it in the
        // background instead, so the first screen that asks gets it.
    }

    private func adopt(_ rooms: [Classroom], campuses: [String]) {
        self.rooms = rooms
        self.campuses = campuses
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

        // Disk first, so callers have a catalogue to draw within a frame or
        // two rather than after four network round-trips.
        if rooms.isEmpty, let cached = await Self.cachedCatalogue() {
            adopt(cached.rooms, campuses: cached.campuses)
        }

        do {
            // Three independent catalogues; fetch together and join locally.
            async let roomsTask = fetch("/spazi/aula", as: [ClassroomDTO].self)
            async let buildingsTask = fetch("/spazi/edificio", as: [BuildingDTO].self)
            async let campusesTask = fetch("/spazi/campus", as: [CampusDTO].self)
            async let floorsTask = fetch("/spazi/piano", as: [FloorDTO].self)

            let (rawRooms, rawBuildings, rawCampuses, rawFloors) =
                try await (roomsTask, buildingsTask, campusesTask, floorsTask)

            let joined = await Self.join(
                rooms: rawRooms, buildings: rawBuildings, campuses: rawCampuses, floors: rawFloors)

            log.notice("rooms: \(rawRooms.count, privacy: .public) in catalogue, \(joined.rooms.count, privacy: .public) usable")
            adopt(joined.rooms, campuses: joined.campuses)
            await Self.cache(joined.rooms)
        } catch {
            log.error("Room catalogue failed: \(error.localizedDescription)")
            errorMessage = userFacingMessage(error)
        }
    }

    /// The catalogue as it is held in memory: the rooms, plus the campus list
    /// derived from them once instead of per read.
    nonisolated private struct Catalogue: Sendable {
        let rooms: [Classroom]
        let campuses: [String]

        nonisolated init(_ rooms: [Classroom]) {
            self.rooms = rooms
            campuses = Array(Set(rooms.compactMap(\.campusName))).sorted()
        }
    }

    /// The join of the four catalogues, off the main actor.
    ///
    /// Four dictionaries and a sort over 350 rooms is not free, and under this
    /// project's main-actor-by-default isolation it all ran on the main thread
    /// while the map was trying to draw.
    @concurrent
    private static func join(rooms rawRooms: [ClassroomDTO], buildings rawBuildings: [BuildingDTO],
                             campuses rawCampuses: [CampusDTO], floors rawFloors: [FloorDTO]) async -> Catalogue {
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

        return Catalogue(joined)
    }

    @concurrent
    private static func cachedCatalogue() async -> Catalogue? {
        guard let cached = DiskCache.load([Classroom].self, as: "rooms"), !cached.value.isEmpty
        else { return nil }
        return Catalogue(cached.value)
    }

    /// Encoding 350 rooms and writing them is a file write; it belongs off the
    /// main thread just as much as the decode does.
    @concurrent
    private static func cache(_ rooms: [Classroom]) async {
        DiskCache.save(rooms, as: "rooms")
    }

    private func fetch<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1, body: "")
        }
        return try await BackgroundJSON.decode(T.self, from: data)
    }
}
