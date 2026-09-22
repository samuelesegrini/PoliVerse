import Foundation

/// The Politecnico's room-occupancy endpoint, callable from both the app and the
/// widget extension.
///
/// The endpoint is public and needs no token, which is what lets an extension fetch
/// rooms on its own rather than depending on the student having opened the Aule
/// libere screen that day.
nonisolated enum RoomOccupancy {
    /// Root of the public maps REST service.
    static let base = URL(string: "https://onlineservices.polimi.it/maps_rest/rest")!

    /// What one occupancy fetch produced.
    enum Result: Sendable {
        /// The room's bookings for the day. An empty array means the room is free all day.
        case busy([FreeRoomsSnapshot.Interval])
        /// The university does not publish this room's bookings — the endpoint answers
        /// `MSG_OCCUPAZIONI_NASCOSTE`. Not the same as free.
        case hidden
        /// The fetch did not produce a usable answer: a transport error, a non-200
        /// response, or a payload that would not decode.
        case failed
    }

    /// Fetches a campus's bookings for a day, in batches, stopping at a deadline.
    ///
    /// A widget extension may be halted before every request finishes, so a snapshot
    /// containing the rooms that did answer is written rather than none at all. Rooms
    /// that did not answer — failed or hidden — are omitted rather than reported free.
    ///
    /// - Parameters:
    ///   - campus: The campus name to stamp on the snapshot.
    ///   - rooms: The rooms to ask about.
    ///   - day: The day to ask about.
    ///   - deadline: When to stop starting batches.
    ///   - concurrency: How many rooms are fetched at once.
    ///   - session: The URL session to fetch through.
    /// - Returns: A snapshot for the rooms that answered, each room's bookings sorted
    ///   by start.
    /// Fetches one room's bookings for one day.
    ///
    /// A hidden room is reported as ``Result/hidden`` and a failure as
    /// ``Result/failed``, never as free: callers must not turn “cannot tell” into “it
    /// is empty”.
    ///
    /// - Parameters:
    ///   - id: The room's occupancy identifier from the catalogue.
    ///   - day: The day to ask about.
    ///   - session: The URL session to fetch through.
    /// - Returns: The bookings, or why there are none to report. Never throws; the
    ///   20-second timeout and every error land in ``Result/failed``.
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

/// One busy band as `/ricerca/aula/occupazione` sends it.
///
/// Times only — the date is the one that was asked for — and they are Rome wall
/// clock, like every other timestamp these services produce.
nonisolated struct OccupancyBand: Decodable, Sendable {
    /// Start time of the band, as wall clock.
    let inizio: String?
    /// End time of the band, as wall clock.
    let fine: String?

    /// Resolves the band's times against a day.
    ///
    /// The end is clamped to be no earlier than the start, so a malformed pair cannot
    /// produce an inverted interval.
    ///
    /// - Parameter day: The day the times belong to.
    /// - Returns: The interval, or `nil` when either time is missing or unparseable.
    func interval(on day: Date) -> FreeRoomsSnapshot.Interval? {
        guard
            let inizio, let fine,
            let start = PoliMiDate.applying(time: inizio, to: day),
            let end = PoliMiDate.applying(time: fine, to: day)
        else { return nil }
        return .init(start: start, end: max(start, end))
    }
}

/// Fetching a whole campus's bookings, for the app and for the widget's own
/// refresh.
nonisolated extension FreeRoomsSnapshot {
    /// A room as the widget needs to ask about it, including the occupancy identifier
    /// that only the catalogue holds.
    ///
    /// Written per campus by the app under ``catalogueCacheName``, since an extension
    /// has no catalogue of its own.
    nonisolated struct RoomRef: Codable, Sendable, Equatable {
        /// The room's identifier in the catalogue.
        var id: String
        /// The room's name as it is signposted.
        var name: String
        /// The building it is in, when known.
        var building: String?
        /// Seating capacity, when known.
        var seats: Int?
        /// The identifier ``RoomOccupancy/fetch(occupancyID:on:session:)`` takes.
        var occupancyID: String
    }

    /// The record name the per-campus ``RoomRef`` list is stored under.
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
