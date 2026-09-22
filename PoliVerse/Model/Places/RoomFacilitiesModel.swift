import Foundation
import Observation
import OSLog

/// What a room is equipped with, and what is installed on its machines.
///
/// Both endpoints are public and keyed on `idaula`, like occupancy. The fetches sit on
/// a ``ResourceLoader``, so concurrent callers share one request, results outlive the
/// view that asked for them, and the rows either side of the one on screen can be
/// warmed through ``prefetch(_:)``.
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
    /// Fetches, caches and coalesces the two calls per room.
    private let loader: ResourceLoader<String, RoomDetails>

    /// Equipment and software together: they are always wanted together, so one entry
    /// means one cache slot and one round of coalescing instead of two.
    nonisolated struct RoomDetails: Sendable {
        /// What the room is equipped with.
        let equipment: [RoomFacility]
        /// What is installed on its machines.
        let software: [RoomFacility]
    }

    /// Builds the loader, with an hour's lifetime per room and room for 256 of them.
    ///
    /// - Parameter http: The transport the two public calls go through.
    init(http: any HTTP = PublicHTTP()) {
        loader = ResourceLoader(
            // A room's projector does not move; an hour is conservative.
            lifetime: .seconds(3600),
            capacity: 256
        ) { id in
            async let kit = Self.fetch(path: "dotazioni", id: id, http: http)
            async let apps = Self.fetch(path: "software", id: id, http: http)
            let (loadedKit, loadedApps) = await (kit, apps)
            // Both failing is a failure; one failing is a room with no
            // software, which is the normal case.
            guard loadedKit != nil || loadedApps != nil else { return nil }
            return RoomDetails(equipment: loadedKit ?? [], software: loadedApps ?? [])
        }
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
        guard let id, !isLoaded(id) else { return }
        guard let details = await loader.value(for: id) else { return }
        equipment[id] = details.equipment
        software[id] = details.software
        log.notice("room \(id, privacy: .public): \(details.equipment.count, privacy: .public) dotazioni, \(details.software.count, privacy: .public) software")
    }

    /// Warms rooms the student has not opened yet.
    ///
    /// Detached at background priority and never awaited, so it cannot delay the room
    /// actually being looked at. Rooms already held are skipped.
    ///
    /// - Parameter rooms: The rooms to warm.
    func prefetch(_ rooms: some Sequence<Classroom>) {
        let ids = rooms.compactMap(\.occupancyID).filter { !isLoaded($0) }
        guard !ids.isEmpty else { return }
        Task.detached(priority: .background) { [loader] in
            await loader.prefetch(ids)
        }
    }

    /// Waits for any warming to finish.
    ///
    /// Used by the background refresh, which has roughly thirty seconds and must not
    /// report success before the work has landed.
    func settle() async {
        await loader.settle()
    }

    /// Discards everything held, and empties the loader's cache.
    func clear() {
        equipment.removeAll()
        software.removeAll()
        Task { [loader] in await loader.clear() }
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
    private static func fetch(
        path: String, id: String, http: any HTTP
    ) async -> [RoomFacility]? {
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
