import Foundation
import Observation
import OSLog

/// Which rooms are free, and when.
///
/// ## How this endpoint was found
///
/// Two dead ends came first, and both are worth keeping written down.
///
/// The CEDA hosts and PoliNetwork are genuinely unreachable off campus. Then
/// `ws_aule` — `/cata/aule?inizio=…&fine=…&sede=…`, straight out of the
/// official bundle — turned out to exist but to be closed to student accounts:
/// its own profile (3) answers "Utente non abilitato", and the account's own
/// profile answers "Scope OAuth non valido". It backs `registroLezioni`, a
/// lecture register, and is staff-only.
///
/// The answer was in neither place. `maps_rest` publishes a **WADL** at
/// `/rest/application.wadl` — 151 endpoints, machine-readable, no token — and
/// among them:
///
/// ```
/// GET /ricerca/aula/occupazione/{idaula}/{yyyy-MM-dd}
///   → [{"inizio":"08:15","fine":"10:15"}, …]
/// ```
///
/// Public, unauthenticated, date-sensitive: Christmas Day and mid-August
/// return `[]`, a teaching day returns the booked bands. Some rooms answer
/// `MSG_OCCUPAZIONI_NASCOSTE` — the university hides those deliberately, and
/// they are reported as unknown rather than guessed at.
///
/// The lesson for next time: ask the service to describe itself before
/// guessing paths. One WADL fetch would have saved both dead ends.
///
/// ## Cost
///
/// Occupancy is per room, so a campus means one request each — 158 for Milano
/// Leonardo, the largest. They run concurrently with a bounded pool and are
/// cached per room and day, so a day already looked at costs nothing.
@Observable
final class FreeRoomsService {
    private(set) var rooms: [RoomSchedule] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Rooms whose occupancy the university does not publish. Named rather
    /// than silently dropped: "we cannot tell" is not "it is free".
    private(set) var hiddenRooms: [String] = []
    /// How far through the fetch we are, for a screen that takes a moment.
    private(set) var progress: (done: Int, total: Int) = (0, 0)

    var day: Date = .now
    var campus: String?

    private let catalogue: RoomsService
    private let session: URLSession
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "aule")
    private let base = URL(string: "https://onlineservices.polimi.it/maps_rest/rest")!

    private var loadedKey: String?

    /// Occupancy, keyed by room and day.
    ///
    /// Was a plain dictionary, which could not coalesce: opening a room from
    /// search while the campus pass was still running fetched it twice. The
    /// loader shares one request per room and lets the rest of the campus be
    /// warmed in the background.
    private let loader: ResourceLoader<OccupancyKey, [RoomBooking]>

    nonisolated struct OccupancyKey: Hashable, Sendable {
        let roomID: String
        let occupancyID: String
        let day: String
    }

    /// At most this many requests in flight. A campus is up to 158 rooms;
    /// firing them all at once is rude to a public service and gets slower,
    /// not faster.
    private let concurrency = 8

    convenience init(catalogue: RoomsService, preview rooms: [RoomSchedule]) {
        self.init(catalogue: catalogue)
        self.rooms = rooms
        self.skipsLoading = true
    }

    private var skipsLoading = false

    init(catalogue: RoomsService, session: URLSession = .shared) {
        self.catalogue = catalogue
        self.session = session
        let base = self.base
        loader = ResourceLoader(
            // A day's timetable does not change while the app is open, and a
            // past day never changes at all.
            lifetime: .seconds(1800),
            capacity: 512
        ) { key in
            let day = PoliMiDate.romeCalendar.date(
                from: PoliMiDate.romeCalendar.dateComponents(
                    [.year, .month, .day],
                    from: PoliMiDate.parse(key.day) ?? .now)) ?? .now
            let result = await Self.occupancy(
                occupancyID: key.occupancyID, roomID: key.roomID,
                on: key.day, day: day, base: base, session: session)
            guard case .bookings(let bookings) = result else { return nil }
            return bookings
        }
    }

    var campuses: [String] { catalogue.campuses }

    /// 08:00–20:00 in Rome. Outside those hours every room is trivially free,
    /// which is true and useless — the building is shut.
    var teachingDay: DateInterval {
        let start = PoliMiDate.time(8, on: day)
        let end = PoliMiDate.time(20, on: day)
        return DateInterval(start: start, end: max(start, end))
    }

    func freeRooms(minimumMinutes: Int = 30) -> [(room: RoomSchedule, slots: [DateInterval])] {
        let window = teachingDay
        return rooms
            .map { ($0, $0.freeSlots(in: window, minimumMinutes: minimumMinutes)) }
            .filter { !$0.1.isEmpty }
            .sorted { left, right in
                let leftFree = left.1.reduce(0) { $0 + $1.duration }
                let rightFree = right.1.reduce(0) { $0 + $1.duration }
                if leftFree != rightFree { return leftFree > rightFree }
                return left.0.name < right.0.name
            }
    }

    /// Rooms free right now — the question actually being asked by someone
    /// looking for somewhere to sit.
    func freeNow() -> [RoomSchedule] {
        let now = Date.now
        guard teachingDay.contains(now) else { return [] }
        let window = DateInterval(
            start: now, end: min(now.addingTimeInterval(1800), teachingDay.end))
        return rooms.filter { $0.isFree(during: window) }.sorted { $0.name < $1.name }
    }

    func load(force: Bool = false) async {
        guard !skipsLoading else { return }
        await catalogue.load()
        if campus == nil { campus = catalogue.campuses.first }

        let key = "\(PoliMiDate.queryString(day))|\(campus ?? "-")"
        guard !isLoading, force || key != loadedKey else { return }
        isLoading = true
        errorMessage = nil
        hiddenRooms = []
        defer { isLoading = false }

        let wanted = catalogue.rooms(matching: "", campus: campus)
            .filter { $0.occupancyID != nil }
        guard !wanted.isEmpty else {
            rooms = []
            errorMessage = String(localized: "Nessuna aula in questa sede.")
            return
        }

        let stamp = PoliMiDate.queryString(day)
        progress = (0, wanted.count)

        var loaded: [RoomSchedule] = []
        var hidden: [String] = []

        // Batched rather than one big task group: `load()` is main-actor
        // isolated and a group body cannot touch that state. A batch at a time
        // keeps progress here, where the rest of the state lives, and still
        // runs `concurrency` requests at once — now through the loader, so a
        // room already being fetched for a detail screen is not fetched twice.
        for batch in stride(from: 0, to: wanted.count, by: concurrency) {
            let slice = Array(wanted[batch..<min(batch + concurrency, wanted.count)])

            var fetched: [String: [RoomBooking]?] = [:]
            await withTaskGroup(of: (String, [RoomBooking]?).self) { group in
                for room in slice {
                    guard let occupancyID = room.occupancyID else { continue }
                    let key = OccupancyKey(
                        roomID: room.id, occupancyID: occupancyID, day: stamp)
                    group.addTask { [loader] in
                        (room.id, await loader.value(for: key))
                    }
                }
                for await (id, bookings) in group { fetched[id] = bookings }
            }

            for room in slice {
                switch fetched[room.id] {
                case .some(.some(let bookings)):
                    loaded.append(RoomSchedule(
                        id: room.id,
                        name: room.id,
                        building: room.buildingName,
                        seats: room.capacity > 0 ? room.capacity : nil,
                        occupancyID: room.occupancyID,
                        bookings: bookings))
                default:
                    // Hidden or failed: either way not listed as free. A room
                    // we could not ask about is a room we know nothing about.
                    hidden.append(room.id)
                }
            }
            progress = (min(batch + concurrency, wanted.count), wanted.count)
        }

        rooms = loaded
        hiddenRooms = hidden.sorted()
        loadedKey = key
        let booked = loaded.reduce(0) { $0 + $1.bookings.count }
        log.notice("aule \(stamp, privacy: .public): \(loaded.count, privacy: .public) rooms, \(booked, privacy: .public) bookings, \(hidden.count, privacy: .public) hidden, \(self.freeRooms().count, privacy: .public) with free time")
    }

    /// One room's bookings for the day being shown.
    ///
    /// Serves the room detail, which must not pay for the campus-wide pass:
    /// that one is 150 requests and its cache is keyed by campus and day, so
    /// it cannot answer for a single room opened from anywhere else. Shares
    /// the same per-room cache, so a room already seen costs nothing.
    ///
    /// Returns nil when the room's occupancy is hidden or the call fails —
    /// both mean "we cannot say", which the caller must not render as "free".
    func bookings(for room: Classroom) async -> [RoomBooking]? {
        guard let occupancyID = room.occupancyID else { return nil }
        let key = OccupancyKey(
            roomID: room.id, occupancyID: occupancyID,
            day: PoliMiDate.queryString(day))
        return await loader.value(for: key)
    }

    /// Warms the rooms around the one being looked at.
    ///
    /// Never awaited and at background priority: the room the user actually
    /// opened must not wait on its neighbours.
    func prefetch(_ rooms: some Sequence<Classroom>) {
        let stamp = PoliMiDate.queryString(day)
        let keys = rooms.compactMap { room -> OccupancyKey? in
            guard let occupancyID = room.occupancyID else { return nil }
            return OccupancyKey(roomID: room.id, occupancyID: occupancyID, day: stamp)
        }
        guard !keys.isEmpty else { return }
        Task.detached(priority: .background) { [loader] in
            await loader.prefetch(keys)
        }
    }

    private enum OccupancyResult: Sendable {
        case bookings([RoomBooking])
        /// `MSG_OCCUPAZIONI_NASCOSTE` — the university does not publish this
        /// room's bookings.
        case hidden
        case failed
    }

    /// Static and parameterised so it carries no actor-isolated state and can
    /// run concurrently off the main actor.
    private static func occupancy(
        occupancyID id: String, roomID: String, on stamp: String, day: Date,
        base: URL, session: URLSession
    ) async -> OccupancyResult {
        let url = base.appendingPathComponent("ricerca/aula/occupazione/\(id)/\(stamp)")
        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            let body = String(data: data, encoding: .utf8) ?? ""

            // The university hides some rooms' bookings deliberately. Reported
            // as unknown, never as free — "we cannot tell" is not "it is
            // empty", and the difference is someone walking into a lecture.
            if body.contains("OCCUPAZIONI_NASCOSTE") { return .hidden }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failed
            }

            let bands = try JSONDecoder().decode([OccupancyBand].self, from: data)
            return .bookings(bands.enumerated().compactMap { index, band in
                band.toBooking(roomID: roomID, on: day, index: index)
            })
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

    func toBooking(roomID: String, on day: Date, index: Int) -> RoomBooking? {
        guard
            let inizio, let fine,
            let start = PoliMiDate.applying(time: inizio, to: day),
            let end = PoliMiDate.applying(time: fine, to: day)
        else { return nil }
        return RoomBooking(
            id: "\(roomID)-\(index)", start: start, end: max(start, end), title: nil)
    }
}
