import Foundation
import Observation
import OSLog

/// What a room is equipped with, and what is installed on its machines.
///
/// Both endpoints are public and keyed on `idaula`, like occupancy. The fetches go
/// through a ``Loader`` of ``RoomDetailsResource``, so concurrent callers share one
/// request, results outlive the view that asked for them, and the rows either side of
/// the one on screen can be warmed through ``prefetch(_:)``.
@Observable
final class RoomFacilitiesModel {
    /// A room's equipment, by `idaula`, for the views to read. The loader behind it holds
    /// the truth.
    private(set) var equipment: [String: [RoomFacility]] = [:]
    /// A room's installed software, by `idaula`. Empty for any room that is not a computer
    /// laboratory.
    private(set) var software: [String: [RoomFacility]] = [:]

    /// Diagnostic log for this type, under the `aule` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "aule")
    /// Fetches, caches and joins the two calls per room.
    private let loader: Loader<RoomDetailsResource>
    /// Fetches and keeps the floor plans, so one prepared before a lecture opens at once.
    private let plans: Loader<FloorPlanResource>
    /// Public data: nobody's account.
    private let env = Env.public()

    /// Builds the loader.
    ///
    /// - Parameter http: The transport the two public calls go through.
    ///   - plans: The floor plans' resource.
    init(http: any HTTP = PublicHTTP(), plans: FloorPlanResource = FloorPlanResource()) {
        loader = Loader(RoomDetailsResource(http: http))
        self.plans = Loader(plans)
    }

    /// A room's floor plan, as the endpoint sends it: held, joined or fetched.
    ///
    /// - Parameter room: The room, whose ``Classroom/floorPlanURL`` is used.
    /// - Returns: The image's bytes, or `nil` when the room has no plan or it
    ///   could not be fetched.
    func floorPlan(for room: Classroom) async throws -> Data? {
        guard let url = room.floorPlanURL else { return nil }
        return try await plans.value(url, env: env).value
    }

    /// Warms the floor plans of rooms about to be opened, in the speculative lane.
    ///
    /// - Parameter rooms: The rooms.
    func prefetchFloorPlans(_ rooms: some Sequence<Classroom>) {
        let urls = rooms.compactMap(\.floorPlanURL)
        guard !urls.isEmpty else { return }
        Task(name: "floor plans warm") { [plans, env] in await plans.warm(urls, env: env) }
    }

    /// Whether a floor plan is held fresh, so opening the room draws it at once.
    ///
    /// - Parameter room: The room.
    func hasFloorPlan(for room: Classroom) async -> Bool {
        guard let url = room.floorPlanURL else { return false }
        return await plans.isHeld(url, env: env)
    }

    /// Creates a model already holding the same equipment for every sample room.
    ///
    /// - Parameter facilities: The equipment to report.
    convenience init(preview facilities: [RoomFacility]) {
        self.init()
        for id in Classroom.samples().compactMap(\.occupancyID) {
            equipment[id] = facilities
            software[id] = []
        }
    }

    /// Whether a room's details are already held.
    ///
    /// - Parameter id: The room's `idaula`.
    /// - Returns: `true` when both lists are present.
    func isLoaded(_ id: String) -> Bool {
        equipment[id] != nil && software[id] != nil
    }

    /// Loads a room's details.
    ///
    /// - Parameter room: The room, whose ``Classroom/occupancyID`` is used.
    func load(for room: Classroom) async {
        await load(id: room.occupancyID)
    }

    /// Loads one room's details, joining any fetch already running for it.
    ///
    /// Does nothing without an id, when the details are already held, or when the fetch
    /// fails.
    ///
    /// - Parameter id: The room's `idaula`.
    func load(id: String?) async {
        guard let id, !isLoaded(id),
              let details = try? await loader.value(id, env: env).value else { return }
        equipment[id] = details.equipment
        software[id] = details.software
        log.notice("room \(id, privacy: .public): \(details.equipment.count, privacy: .public) dotazioni, \(details.software.count, privacy: .public) software")
    }

    /// Warms rooms the student has not opened yet.
    ///
    /// At `.utility` and never awaited, so it cannot delay the room actually being
    /// looked at; opening a room being warmed raises that fetch to the screen's
    /// priority. Rooms already held are skipped, and nothing is warmed while the phone
    /// is hot or saving power (``DevicePressure``).
    ///
    /// - Parameter rooms: The rooms to warm.
    func prefetch(_ rooms: some Sequence<Classroom>) {
        let rooms = Array(rooms)
        Task(name: "facilities warm") { await warm(rooms) }
    }

    /// Starts warming rooms' equipment and floor plans and returns once the
    /// fetches are under way, for a caller that then waits on ``settle()``.
    ///
    /// - Parameter rooms: The rooms to warm.
    func warm(_ rooms: [Classroom], plans withPlans: Bool = false) async {
        guard !DevicePressure.isHigh else { return }
        let ids = rooms.compactMap(\.occupancyID).filter { !isLoaded($0) }
        if !ids.isEmpty { await loader.warm(ids, env: env) }
        let urls = withPlans ? rooms.compactMap(\.floorPlanURL) : []
        if !urls.isEmpty { await plans.warm(urls, env: env) }
    }

    /// Waits for any warming to finish.
    ///
    /// Used by the background refresh, which has roughly thirty seconds and must not
    /// report success before the work has landed.
    func settle() async {
        await loader.settle()
        await plans.settle()
    }

    /// Discards everything held, and empties the loader's cache.
    func clear() {
        equipment.removeAll()
        software.removeAll()
        Task { [loader, plans] in
            await loader.clear()
            await plans.clear()
        }
    }
}

/// A room's equipment and software, from the two public endpoints keyed on `idaula`.
nonisolated struct RoomDetailsResource: Resource {
    /// Equipment and software together: they are always wanted together, so one entry
    /// means one cache slot and one fetch to join instead of two.
    struct Details: Sendable {
        /// What the room is equipped with.
        let equipment: [RoomFacility]
        /// What is installed on its machines.
        let software: [RoomFacility]
    }

    /// Both lists failed for a room.
    struct Unavailable: Error {}

    static let id = "room-details"
    /// A room's projector does not move; an hour is conservative.
    static let ttl: TimeInterval = 3600
    static let persistence = Persistence.memory
    static let capacity = 256

    /// The transport the two calls go through.
    let http: any HTTP

    @concurrent
    func fetch(_ key: String, env: Env, previous: Details?) async throws -> Details {
        async let kit = Self.list(path: "dotazioni", id: key, http: http)
        async let apps = Self.list(path: "software", id: key, http: http)
        let (loadedKit, loadedApps) = await (kit, apps)
        // Both failing is a failure; one failing is a room with no software,
        // which is the normal case.
        guard loadedKit != nil || loadedApps != nil else { throw Unavailable() }
        return Details(equipment: loadedKit ?? [], software: loadedApps ?? [])
    }

    func sample(_ key: String) -> Details? {
        Details(equipment: RoomFacility.samples(), software: [])
    }

    /// Fetches one of the two facility lists for a room.
    ///
    /// Items with no name are dropped.
    ///
    /// - Parameters:
    ///   - path: `dotazioni` or `software`.
    ///   - id: The room's `idaula`.
    ///   - http: The transport.
    /// - Returns: The items, or `nil` on any failure. `nil` rather than throwing, because
    ///   one of the two endpoints failing usually means a room with no software listed.
    private static func list(path: String, id: String, http: any HTTP) async -> [RoomFacility]? {
        do {
            let data = try await http.data(for: APIRequest(
                host: .maps, path: "/ricerca/aula/\(path)/\(id)", authenticated: false))
            return try await BackgroundJSON.decode([RoomFacility].self, from: data)
                .filter { !$0.name.isEmpty }
        } catch {
            return nil
        }
    }
}

/// A floor's plan with one room highlighted, from the public maps service.
///
/// Through a ``Loader`` rather than straight from the view, so a plan prepared
/// before a lecture is there when the room is opened, and two views of one room
/// cost one request. Held in memory for a day: plans change when a building is
/// rearranged, not during a week.
nonisolated struct FloorPlanResource: Resource {
    typealias Key = URL
    typealias Value = Data

    /// The plan could not be fetched.
    struct Unavailable: Error {}

    static let id = "floor-plan"
    static let ttl: TimeInterval = 86_400
    static let persistence = Persistence.memory
    static let capacity = 24

    /// The session the image is fetched through.
    var session: URLSession = .shared

    @concurrent
    func fetch(_ key: URL, env: Env, previous: Data?) async throws -> Data {
        let session = session
        return try await RequestGate.shared.run(host: ServiceDirectory.Service.maps.rawValue) {
            var request = URLRequest(url: key)
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 == 200, !data.isEmpty else {
                throw Unavailable()
            }
            return data
        }
    }
}
