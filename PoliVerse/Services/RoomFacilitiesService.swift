import Foundation
import Observation
import OSLog

/// What a room is equipped with, and what is installed on its machines.
///
/// Both endpoints are public and need no token, and both are keyed on
/// `idaula` like the occupancy call. Results are cached for the session: a
/// room's projector does not move.
@Observable
final class RoomFacilitiesService {
    /// Keyed by `idaula`.
    private(set) var equipment: [String: [RoomFacility]] = [:]
    private(set) var software: [String: [RoomFacility]] = [:]
    private(set) var loading: Set<String> = []

    private let session: URLSession
    private let base = URL(string: "https://onlineservices.polimi.it/maps_rest/rest/ricerca/aula")!
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "aule")

    convenience init(preview facilities: [RoomFacility]) {
        self.init()
        // Keyed under the mock rooms' ids so any preview room shows something.
        for id in MockData.classrooms().compactMap(\.occupancyID) {
            equipment[id] = facilities
            software[id] = []
        }
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Whether this room has been asked about yet. Distinguishes "nothing
    /// recorded" from "not looked up", which otherwise both render as empty.
    func isLoaded(_ id: String) -> Bool {
        equipment[id] != nil && software[id] != nil
    }

    func load(for room: Classroom) async {
        await load(id: room.occupancyID)
    }

    func load(id: String?) async {
        guard let id, !isLoaded(id), !loading.contains(id) else { return }
        loading.insert(id)
        defer { loading.remove(id) }

        let base = base
        let session = session
        async let kit = Self.fetch(path: "dotazioni", id: id, base: base, session: session)
        async let apps = Self.fetch(path: "software", id: id, base: base, session: session)
        let (loadedKit, loadedApps) = await (kit, apps)

        // Stored even when empty: that is the answer for most rooms, and
        // re-asking on every appearance would be pointless traffic.
        equipment[id] = loadedKit ?? []
        software[id] = loadedApps ?? []
        log.notice("room \(id, privacy: .public): \(loadedKit?.count ?? 0, privacy: .public) dotazioni, \(loadedApps?.count ?? 0, privacy: .public) software")
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
            return try JSONDecoder().decode([RoomFacility].self, from: data)
                .filter { !$0.name.isEmpty }
        } catch {
            return nil
        }
    }
}
