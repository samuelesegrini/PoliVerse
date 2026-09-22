import Foundation
import Observation
import OSLog

/// The room catalogue, from the Politecnico's public maps service.
///
/// Every room on campus with its building, floor, campus and capacity, joined from
/// four independent catalogues — rooms, buildings, campuses and floors — that share
/// the `csi*` codes as foreign keys. Unauthenticated throughout.
///
/// This is the catalogue only. What is happening in a room comes from the bookings
/// service and lives in ``FreeRoomsModel``: a different backend, with different
/// authorisation and a different lifetime, so joining the two here would tie the
/// catalogue's availability to a token it does not need.
///
/// ## Loading
///
/// The catalogue changes rarely, so ``load(force:)`` serves the ``DiskCache`` copy
/// first and fetches only when nothing is held or a refresh is asked for. Reading,
/// joining and writing the catalogue all happen off the main actor.
@Observable
final class RoomsModel {
    /// Every room in the catalogue, sorted by code.
    private(set) var rooms: [Classroom] = []
    /// The campuses present, sorted.
    ///
    /// Stored rather than computed, because view bodies read it and deriving a set over
    /// the whole catalogue on every render is work the main thread need not repeat.
    private(set) var campuses: [String] = []
    /// `true` while a load is in flight.
    private(set) var isLoading = false
    /// The last load's error, or `nil` when it succeeded.
    private(set) var errorMessage: String?

    /// Diagnostic log for this type, under the `rooms` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "rooms")
    /// The transport. The base URL comes from ``ServiceDirectory/Service/maps`` rather
    /// than from here, so the models that read this service cannot drift apart.
    private let http: any HTTP
    /// Which ``DiskCache`` record holds the catalogue.
    ///
    /// Injectable only so a test cannot overwrite the real one. The cache is deliberately
    /// not keyed by account — a campus is the same campus for everyone.
    private let cacheName: String

    /// Seeds the catalogue and stops it fetching, for previews.
    ///
    /// The maps service is unauthenticated and has no sample path of its own, so without
    /// this every preview of a room screen would reach the network.
    ///
    /// - Parameter rooms: The catalogue to report.
    convenience init(preview rooms: [Classroom]) {
        self.init()
        self.rooms = rooms
        self.campuses = Array(Set(rooms.compactMap(\.campusName))).sorted()
        self.skipsLoading = true
    }

    /// Set by the preview initialiser; makes ``load(force:)`` do nothing.
    private var skipsLoading = false

    /// Creates the model without reading anything.
    ///
    /// The cached catalogue is deliberately not read here: this runs while the app is
    /// launching, and decoding the whole catalogue on the main thread would stall the
    /// first frame. ``load(force:)`` reads it in the background instead.
    ///
    /// - Parameters:
    ///   - http: The transport.
    ///   - cacheName: Which ``DiskCache`` record holds the catalogue.
    init(http: any HTTP = PublicHTTP(), cacheName: String = "rooms") {
        self.http = http
        self.cacheName = cacheName
        // The cached catalogue is *not* read here: this runs while the app is
        // launching, and decoding 350 rooms from disk on the main thread is a
        // stall before anything is on screen. ``load(force:)`` reads it in the
        // background instead, so the first screen that asks gets it.
    }

    /// Publishes a catalogue and its campus list together.
    ///
    /// - Parameters:
    ///   - rooms: The rooms to publish.
    ///   - campuses: The campuses derived from them.
    private func adopt(_ rooms: [Classroom], campuses: [String]) {
        self.rooms = rooms
        self.campuses = campuses
    }

    /// Loads the catalogue, serving the cached copy first.
    ///
    /// Returns immediately when a load is in flight, or when a catalogue is already held
    /// and `force` is `false`. The four catalogues are fetched concurrently and joined
    /// off the main actor; the result is cached. A failure leaves whatever was held in
    /// place and sets ``errorMessage``.
    ///
    /// - Parameter force: Refetches even when a catalogue is already held.
    func load(force: Bool = false) async {
        guard !skipsLoading else { return }
        guard !isLoading, force || rooms.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Disk first, so callers have a catalogue to draw within a frame or
        // two rather than after four network round-trips.
        if rooms.isEmpty, let cached = await Self.cachedCatalogue(cacheName) {
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
            await Self.cache(joined.rooms, as: cacheName)
        } catch {
            log.error("Room catalogue failed: \(error.localizedDescription)")
            errorMessage = userFacingMessage(error)
        }
    }

    /// The catalogue as it is held in memory: the rooms, and the campus list derived from
    /// them once rather than per read.
    nonisolated private struct Catalogue: Sendable {
        /// The rooms.
        let rooms: [Classroom]
        /// The campuses present, sorted.
        let campuses: [String]

        /// Derives the campus list from the rooms.
        ///
        /// - Parameter rooms: The rooms to hold.
        nonisolated init(_ rooms: [Classroom]) {
            self.rooms = rooms
            campuses = Array(Set(rooms.compactMap(\.campusName))).sorted()
        }
    }

    /// Joins the four catalogues into rooms, on the global executor.
    ///
    /// Rooms are indexed against buildings, campuses and floors by their shared codes;
    /// unusable rooms are dropped by ``ClassroomDTO/toClassroom()``. Runs off the main
    /// actor because four dictionaries and a sort over the whole catalogue would
    /// otherwise happen while the map is drawing.
    ///
    /// - Parameters:
    ///   - rawRooms: The room catalogue.
    ///   - rawBuildings: The building catalogue.
    ///   - rawCampuses: The campus catalogue.
    ///   - rawFloors: The floor catalogue.
    /// - Returns: The joined rooms, sorted by code, with their campus list.
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

    /// Reads the cached catalogue on the global executor.
    ///
    /// - Parameter name: The ``DiskCache`` record.
    /// - Returns: The catalogue, or `nil` when nothing usable is cached.
    @concurrent
    private static func cachedCatalogue(_ name: String) async -> Catalogue? {
        guard let cached = DiskCache.load([Classroom].self, as: name), !cached.value.isEmpty
        else { return nil }
        return Catalogue(cached.value)
    }

    /// Encodes and writes the catalogue on the global executor.
    ///
    /// - Parameters:
    ///   - rooms: The rooms to cache.
    ///   - name: The ``DiskCache`` record.
    @concurrent
    private static func cache(_ rooms: [Classroom], as name: String) async {
        DiskCache.save(rooms, as: name)
    }

    /// Fetches and decodes one unauthenticated maps-service catalogue.
    ///
    /// - Parameters:
    ///   - path: The catalogue's path below the maps host.
    ///   - type: The shape to decode.
    /// - Returns: The decoded catalogue.
    /// - Throws: ``APIError``.
    private func fetch<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await http.data(for: APIRequest(host: .maps, path: path,
                                                       authenticated: false))
        return try await BackgroundJSON.decode(T.self, from: data)
    }
}
/// ``RoomsModel`` satisfies ``RoomCatalogue`` as it stands.
///
/// Declared here rather than beside the protocol: ``RoomCatalogue`` refines
/// `Sendable`, and a `Sendable` conformance stated in another file is
/// retroactive.
extension RoomsModel: RoomCatalogue {}
