import Foundation

/// The occupancy endpoint, shared by the app and the widget.
///
/// It lives here because the widget fetches rooms on its own: a snapshot that
/// only the Aule libere screen could write left the widget empty on every day
/// the student did not open that screen. The endpoint is public and needs no
/// token, which is the only reason an extension can call it at all.
nonisolated enum RoomOccupancy {
    static let base = URL(string: "https://onlineservices.polimi.it/maps_rest/rest")!

    enum Result: Sendable {
        case busy([FreeRoomsSnapshot.Interval])
        /// `MSG_OCCUPAZIONI_NASCOSTE` — the university does not publish this
        /// room's bookings.
        case hidden
        case failed
    }

    static func fetch(
        occupancyID id: String, on day: Date, session: URLSession = .shared
    ) async -> Result {
        let stamp = PoliMiDate.queryString(day)
        let url = base.appendingPathComponent("ricerca/aula/occupazione/\(id)/\(stamp)")
        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)

            // Reported as unknown, never as free — "we cannot tell" is not
            // "it is empty", and the difference is someone walking into a
            // lecture.
            if String(decoding: data, as: UTF8.self).contains("OCCUPAZIONI_NASCOSTE") {
                return .hidden
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failed
            }
            let bands = try JSONDecoder().decode([OccupancyBand].self, from: data)
            return .busy(bands.compactMap { $0.interval(on: day) })
        } catch {
            return .failed
        }
    }
}

/// One busy band, as `/ricerca/aula/occupazione` sends it.
///
/// Times only — the date is the one that was asked for — and they are wall
/// clock in Rome like every other timestamp these services produce.
nonisolated struct OccupancyBand: Decodable, Sendable {
    let inizio: String?
    let fine: String?

    func interval(on day: Date) -> FreeRoomsSnapshot.Interval? {
        guard
            let inizio, let fine,
            let start = PoliMiDate.applying(time: inizio, to: day),
            let end = PoliMiDate.applying(time: fine, to: day)
        else { return nil }
        return .init(start: start, end: max(start, end))
    }
}

nonisolated extension FreeRoomsSnapshot {
    /// A room as the widget needs to ask about it: the catalogue has the
    /// occupancy id, and an extension has no catalogue of its own.
    nonisolated struct RoomRef: Codable, Sendable, Equatable {
        var id: String
        var name: String
        var building: String?
        var seats: Int?
        var occupancyID: String
    }

    /// Per campus, written by the app whenever it has the catalogue.
    static let catalogueCacheName = "free-rooms-catalogue"

    /// Fetches a campus's bookings for `day`, stopping at `deadline`.
    ///
    /// The deadline is the point: a widget extension may be halted before
    /// 150 requests finish, and a snapshot written with the rooms that did
    /// answer is better than none. Rooms that did not answer are left out, not
    /// listed as free — the same rule the app follows for failures.
    static func fetch(
        campus: String, rooms: [RoomRef], day: Date, deadline: Date,
        concurrency: Int = 8, session: URLSession = .shared
    ) async -> FreeRoomsSnapshot {
        var loaded: [Room] = []
        for batch in stride(from: 0, to: rooms.count, by: concurrency) {
            guard Date.now < deadline else { break }
            let slice = rooms[batch..<min(batch + concurrency, rooms.count)]
            await withTaskGroup(of: Room?.self) { group in
                for ref in slice {
                    group.addTask {
                        guard case .busy(let busy) = await RoomOccupancy.fetch(
                            occupancyID: ref.occupancyID, on: day, session: session)
                        else { return nil }
                        return Room(id: ref.id, name: ref.name, building: ref.building,
                                    seats: ref.seats,
                                    busy: busy.sorted { $0.start < $1.start })
                    }
                }
                for await room in group { if let room { loaded.append(room) } }
            }
        }
        return FreeRoomsSnapshot(day: day, campus: campus, rooms: loaded)
    }
}
