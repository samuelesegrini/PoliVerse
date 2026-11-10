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
/// first and fetches once a day or when a refresh is asked for. The fetch goes through
/// a ``Loader`` of ``RoomCatalogueResource``, so a second caller — free rooms awaiting
/// the catalogue while the rooms list loads it — waits for the same fetch instead of
/// being turned away with nothing. Reading, joining and writing the catalogue all
/// happen off the main actor.
@Observable
final class RoomsModel {
    var rooms: [Classroom] { previewCatalogue?.rooms ?? query.value?.rooms ?? [] }
    var campuses: [String] { previewCatalogue?.campuses ?? query.value?.campuses ?? [] }
    var isLoading: Bool { query.isLoading }
    var errorMessage: String? { query.errorMessage }
    private let query: Query<RoomCatalogueResource>
    private var previewCatalogue: Catalogue?

    /// Seeds the catalogue and stops it fetching, for previews.
    ///
    /// The maps service is unauthenticated and has no sample path of its own, so without
    /// this every preview of a room screen would reach the network.
    ///
    /// - Parameter rooms: The catalogue to report.
    convenience init(preview rooms: [Classroom]) {
        self.init()
        self.previewCatalogue = Catalogue(rooms)
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
        query = Query(RoomCatalogueResource(http: http, cacheName: cacheName), account: PublicAccount(http: http))
    }

    func load(force: Bool = false) async {
        guard !skipsLoading else { return }
        await query.load(force: force)
    }

    nonisolated struct Catalogue: Sendable, Equatable {
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
    ///   - rawSites: The site catalogue.
    /// - Returns: The joined rooms, sorted by code, with their campus list.
    @concurrent
    fileprivate static func join(rooms rawRooms: [ClassroomDTO], buildings rawBuildings: [BuildingDTO],
                             campuses rawCampuses: [CampusDTO], floors rawFloors: [FloorDTO],
                             sites rawSites: [SiteDTO]) async -> Catalogue {
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
        let siteNames = Dictionary(
            rawSites.compactMap { dto -> (String, String)? in
                guard let csis = dto.csis, let nome = dto.nome else { return nil }
                return (csis, nome)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let campusSites = Dictionary(
            rawCampuses.compactMap { dto -> (String, String)? in
                guard let csic = dto.csic, let site = dto.csis.flatMap({ siteNames[$0] }) else { return nil }
                return (csic, site)
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
            copy.siteName = building?.csic.flatMap { campusSites[$0] }
            copy.floorName = floorNames[room.floorCode]
            return copy
        }.sorted { $0.id < $1.id }

        return Catalogue(joined)
    }


}
/// ``RoomsModel`` satisfies ``RoomCatalogue`` as it stands.
///
/// Declared here rather than beside the protocol: ``RoomCatalogue`` refines
/// `Sendable`, and a `Sendable` conformance stated in another file is
/// retroactive.
extension RoomsModel: RoomCatalogue {}

/// The room catalogue: rooms, buildings, campuses, floors and sites, joined.
nonisolated struct RoomCatalogueResource: Resource {
    typealias Value = RoomsModel.Catalogue

    static let id = "rooms"
    /// A campus's rooms change between terms, not between launches.
    static let ttl: TimeInterval = 86_400
    /// Kept in ``DiskCache`` by name rather than per account: a campus is the same
    /// campus for everyone.
    static let persistence = Persistence.publicDisk

    /// The transport.
    let http: any HTTP
    /// Which ``DiskCache`` record holds the catalogue.
    let cacheName: String

    func storageName(for key: Whole) -> String { cacheName }

    func save(_ value: Value, to offline: OfflineStore, as name: String, account: String) {
        DiskCache.save(value.rooms, as: name)
    }

    @concurrent
    func read(from offline: OfflineStore, as name: String, account: String) async -> (value: Value, age: TimeInterval)? {
        guard let copy = DiskCache.load([Classroom].self, as: name), !copy.value.isEmpty else { return nil }
        return (RoomsModel.Catalogue(copy.value), Date.now.timeIntervalSince(copy.storedAt))
    }

    @concurrent
    func fetch(_ key: Whole, env: Env, previous: RoomsModel.Catalogue?) async throws -> RoomsModel.Catalogue {
        // Three independent catalogues; fetch together and join locally.
        async let roomsTask = fetch("/spazi/aula", as: [ClassroomDTO].self)
        async let buildingsTask = fetch("/spazi/edificio", as: [BuildingDTO].self)
        async let campusesTask = fetch("/spazi/campus", as: [CampusDTO].self)
        async let floorsTask = fetch("/spazi/piano", as: [FloorDTO].self)
        // The sites only name the campuses' groups: without them the rooms still work.
        async let sitesTask = try? fetch("/spazi/sede", as: [SiteDTO].self)
        let (rawRooms, rawBuildings, rawCampuses, rawFloors) =
            try await (roomsTask, buildingsTask, campusesTask, floorsTask)
        let joined = await RoomsModel.join(
            rooms: rawRooms, buildings: rawBuildings, campuses: rawCampuses, floors: rawFloors,
            sites: await sitesTask ?? [])
        Logger(subsystem: "segrini.samuele.PoliVerse", category: "rooms")
            .notice("rooms: \(rawRooms.count, privacy: .public) in catalogue, \(joined.rooms.count, privacy: .public) usable")
        return joined
    }

    private func fetch<T: Decodable & Sendable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await http.data(for: APIRequest(host: .maps, path: path, authenticated: false))
        return try await BackgroundJSON.decode(T.self, from: data)
    }
}
