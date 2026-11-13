import Foundation
import Observation
import OSLog

/// The services' places and the buildings' access notes, for the new map
/// (``BetaFeature/newMap``).
///
/// One instance for the app, so leaving and reopening the map keeps what was read: the
/// points of interest are refetched after five minutes for the car parks' free spaces, the
/// floors' uses and the access notes once a day.
@MainActor
@Observable
final class CampusServicesModel {
    /// The one the map uses.
    static let shared = CampusServicesModel()

    /// The places from the points of interest.
    private(set) var points: [CampusPlace] = []
    /// The places from the floors' uses, by floor.
    private(set) var floors: [String: [CampusPlace]] = [:]
    /// What a building's entrance is like, and for wheelchair users, by `csie`.
    private(set) var access: [String: BuildingAccess] = [:]
    /// Whether the floors are being read.
    private(set) var readingFloors = false

    /// Diagnostic log, under the `map` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "map")
    private let pointsLoader: Loader<CampusPointsResource>
    private let usesLoader: Loader<FloorUsesResource>
    private let accessLoader: Loader<BuildingAccessResource>
    private let env = Env.public()

    /// Builds the loaders.
    ///
    /// - Parameter http: The transport the public calls go through.
    init(http: any HTTP = PublicHTTP()) {
        pointsLoader = Loader(CampusPointsResource(http: http))
        usesLoader = Loader(FloorUsesResource(http: http))
        accessLoader = Loader(BuildingAccessResource(http: http))
    }

    /// The places of a service, from both sources.
    func places(_ service: CampusService) -> [CampusPlace] {
        service.isPerFloor
            ? floors.values.flatMap { $0 }.filter { $0.service == service }
            : points.filter { $0.service == service }
    }

    /// Reads the points of interest and the access notes; a failure leaves what was held.
    func load() async {
        async let points = try? pointsLoader.value(Whole(), env: env).value
        async let access = try? accessLoader.value(Whole(), env: env).value
        if let points = await points {
            self.points = points
            log.notice("services: \(points.count, privacy: .public) places")
        }
        if let access = await access { self.access = access }
    }

    /// Reads the uses of floors not read yet, eight at a time.
    ///
    /// - Parameter csips: The floors.
    func loadFloors(_ csips: [String]) async {
        let wanted = csips.filter { floors[$0] == nil }
        guard !wanted.isEmpty else { return }
        readingFloors = true
        defer { readingFloors = false }
        for start in stride(from: 0, to: wanted.count, by: 8) {
            let batch = Array(wanted[start..<min(start + 8, wanted.count)])
            let found = await withTaskGroup(of: (String, Set<String>?).self) { group in
                for csip in batch {
                    group.addTask { [usesLoader, env] in
                        (csip, try? await usesLoader.value(csip, env: env).value)
                    }
                }
                var found: [String: Set<String>] = [:]
                for await (csip, uses) in group { if let uses { found[csip] = uses } }
                return found
            }
            for (csip, uses) in found { floors[csip] = CampusPlaces.onFloor(uses, csip: csip) }
        }
    }
}

/// What a building's entrance is like.
nonisolated struct BuildingAccess: Sendable, Equatable {
    /// For everyone: steps, the alternative entrance, the lift.
    let general: String?
    /// For wheelchair users and the blind: ramps, accessible toilets, tactile paths.
    let accessible: String?

    /// Reads the notes from the building catalogue.
    ///
    /// - Parameter buildings: `GET /spazi/edificio`.
    /// - Returns: The notes by `csie`, for the buildings that have any.
    static func parse(_ buildings: [BuildingDTO]) -> [String: BuildingAccess] {
        var result: [String: BuildingAccess] = [:]
        for building in buildings {
            func clean(_ text: String?) -> String? {
                let trimmed = text?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            guard let csie = building.csie else { continue }
            let access = BuildingAccess(general: clean(building.noteAccesso),
                                        accessible: clean(building.noteAccessoDisabili))
            if access.general != nil || access.accessible != nil { result[csie] = access }
        }
        return result
    }
}

/// The points of interest, as places.
nonisolated struct CampusPointsResource: Resource {
    typealias Value = [CampusPlace]
    static let id = "campus-points"
    /// The car parks' free spaces move; the rest does not.
    static let ttl: TimeInterval = 300
    static let persistence = Persistence.memory

    let http: any HTTP

    @concurrent
    func fetch(_ key: Whole, env: Env, previous: [CampusPlace]?) async throws -> [CampusPlace] {
        // The whole of northern Italy, as the official map asks.
        let body = #"{"box":{"sw":{"lat":42.8169,"lng":6.4838},"ne":{"lat":47.068,"lng":13.5803}},"profile":0}"#
        let data = try await http.data(for: APIRequest(host: .maps, path: "/poi/list", method: "POST",
                                                       body: Data(body.utf8), authenticated: false))
        let language = Locale.current.language.languageCode?.identifier == "en" ? "en" : "it"
        return try CampusPlaces.parse(data, language: language)
    }
}

/// A floor's uses.
nonisolated struct FloorUsesResource: Resource {
    typealias Key = String
    typealias Value = Set<String>
    static let id = "floor-uses"
    /// What a floor is used for changes between terms.
    static let ttl: TimeInterval = 86_400
    static let persistence = Persistence.memory
    static let capacity = 512

    let http: any HTTP

    @concurrent
    func fetch(_ key: String, env: Env, previous: Set<String>?) async throws -> Set<String> {
        let data = try await http.data(for: APIRequest(host: .maps, path: "/piano/\(key)/tematismi",
                                                       authenticated: false))
        return try FloorUses.parse(data)
    }
}

/// The buildings' access notes.
nonisolated struct BuildingAccessResource: Resource {
    typealias Value = [String: BuildingAccess]
    static let id = "building-access"
    static let ttl: TimeInterval = 86_400
    static let persistence = Persistence.memory

    let http: any HTTP

    @concurrent
    func fetch(_ key: Whole, env: Env, previous: [String: BuildingAccess]?) async throws -> [String: BuildingAccess] {
        let data = try await http.data(for: APIRequest(host: .maps, path: "/spazi/edificio", authenticated: false))
        return BuildingAccess.parse(try await BackgroundJSON.decode([BuildingDTO].self, from: data))
    }
}
