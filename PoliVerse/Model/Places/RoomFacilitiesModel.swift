import Foundation
import Observation
import OSLog

/// What a room is equipped with, and what is installed on its machines.
///
/// Both endpoints are public and keyed on `idaula` like occupancy. Sitting on
/// ``ResourceLoader`` gets three things the hand-rolled version could not:
/// concurrent callers share one request, results survive the view that asked
/// for them, and the rows either side of the one on screen can be warmed while
/// the user is still reading.
@Observable
final class RoomFacilitiesModel {
    /// Published for the views; the loader behind it is the source of truth.
    private(set) var equipment: [String: [RoomFacility]] = [:]
    private(set) var software: [String: [RoomFacility]] = [:]

    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "aule")
    private let loader: ResourceLoader<String, RoomDetails>

    /// Equipment and software together: they are always wanted together, and
    /// one entry means one cache slot and one round of coalescing instead of
    /// two.
    nonisolated struct RoomDetails: Sendable {
        let equipment: [RoomFacility]
        let software: [RoomFacility]
    }

    init(session: URLSession = .shared) {
        let base = URL(string: "https://onlineservices.polimi.it/maps_rest/rest/ricerca/aula")!
        loader = ResourceLoader(
            // A room's projector does not move; an hour is conservative.
            lifetime: .seconds(3600),
            capacity: 256
        ) { id in
            async let kit = Self.fetch(path: "dotazioni", id: id, base: base, session: session)
            async let apps = Self.fetch(path: "software", id: id, base: base, session: session)
            let (loadedKit, loadedApps) = await (kit, apps)
            // Both failing is a failure; one failing is a room with no
            // software, which is the normal case.
            guard loadedKit != nil || loadedApps != nil else { return nil }
            return RoomDetails(equipment: loadedKit ?? [], software: loadedApps ?? [])
        }
    }

    convenience init(preview facilities: [RoomFacility]) {
        self.init()
        for id in MockData.classrooms().compactMap(\.occupancyID) {
            equipment[id] = facilities
            software[id] = []
        }
    }

    func isLoaded(_ id: String) -> Bool {
        equipment[id] != nil && software[id] != nil
    }

    func load(for room: Classroom) async {
        await load(id: room.occupancyID)
    }

    func load(id: String?) async {
        guard let id, !isLoaded(id) else { return }
        guard let details = await loader.value(for: id) else { return }
        equipment[id] = details.equipment
        software[id] = details.software
        log.notice("room \(id, privacy: .public): \(details.equipment.count, privacy: .public) dotazioni, \(details.software.count, privacy: .public) software")
    }

    /// Warms rooms the user has not opened yet.
    ///
    /// Background priority and never awaited, so it cannot delay the room
    /// actually being looked at.
    func prefetch(_ rooms: some Sequence<Classroom>) {
        let ids = rooms.compactMap(\.occupancyID).filter { !isLoaded($0) }
        guard !ids.isEmpty else { return }
        Task.detached(priority: .background) { [loader] in
            await loader.prefetch(ids)
        }
    }

    /// Waits for any warming to finish. Used by the background refresh, which
    /// has about thirty seconds and must not report success before the work
    /// has actually landed.
    func settle() async {
        await loader.settle()
    }

    func clear() {
        equipment.removeAll()
        software.removeAll()
        Task { [loader] in await loader.clear() }
    }

    private static func fetch(
        path: String, id: String, base: URL, session: URLSession
    ) async -> [RoomFacility]? {
        var request = URLRequest(url: base.appendingPathComponent("\(path)/\(id)"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try await BackgroundJSON.decode([RoomFacility].self, from: data)
                .filter { !$0.name.isEmpty }
        } catch {
            return nil
        }
    }
}
