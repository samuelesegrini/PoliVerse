import Foundation
import WidgetKit
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
    /// When the occupancy on screen was fetched, or nil if it never was.
    ///
    /// Unlike the services backed by ``CachedSlot``, this is not persisted:
    /// occupancy is never restored from disk here, so the only age worth
    /// reporting is the one since this session's fetch.
    private(set) var loadedAt: Date?

    var day: Date = .now
    var campus: String?

    private let catalogue: RoomsService
    private let session: URLSession
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "aule")

    /// Sixty seconds, not the usual five minutes, and keyed on the day and
    /// campus being shown. Occupancy turns over on the lecture boundary, and
    /// this is the one screen where stale data means walking across campus to
    /// an occupied room — so a foregrounding a minute later is worth a refetch
    /// here when it would be waste everywhere else.
    private var window = LoadWindow(interval: 60)

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
    /// Once a launch: the catalogue barely changes, and every load would
    /// otherwise rewrite a file per campus.
    private var publishedCatalogue = false

    init(catalogue: RoomsService, session: URLSession = .shared) {
        self.catalogue = catalogue
        self.session = session
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
            return await Self.occupancy(
                occupancyID: key.occupancyID, roomID: key.roomID, day: day, session: session)
        }
    }

    var campuses: [String] { catalogue.campuses }

    /// Seconds since the occupancy was fetched, for ``FreshnessBar``.
    ///
    /// Computed from `loadedAt` rather than stored as a number, so that every
    /// re-render of the screen reads the current answer rather than the one
    /// that was true at fetch time. It is not a clock: nothing here ticks, so
    /// the bar only moves when the view redraws for some other reason. That is
    /// enough for the question it answers — "is what I am looking at from this
    /// hour?" — and a timer for a bar that is silent under fifteen minutes
    /// would be battery spent on nothing.
    func age(now: Date = .now) -> TimeInterval? {
        loadedAt.map { now.timeIntervalSince($0) }
    }

    var age: TimeInterval? { age(now: .now) }

    /// Records a pass that produced rooms.
    func markLoaded(at date: Date = .now) {
        loadedAt = date
        window.markLoaded(source: "\(PoliMiDate.queryString(day))|\(campus ?? "-")", at: date)
    }

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
        publishWidgetCatalogue()

        let key = "\(PoliMiDate.queryString(day))|\(campus ?? "-")"
        guard !isLoading, window.shouldLoad(force: force, source: key) else { return }
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
        // Only a pass that produced rooms counts. A campus where every request
        // failed leaves `loaded` empty, and stamping that would both suppress
        // the retry a minute later and print "ora" over an empty screen — the
        // same rule ``LoadWindow`` follows for every other service.
        if !loaded.isEmpty { markLoaded() }
        saveWidgetSnapshot()
        let booked = loaded.reduce(0) { $0 + $1.bookings.count }
        log.notice("aule \(stamp, privacy: .public): \(loaded.count, privacy: .public) rooms, \(booked, privacy: .public) bookings, \(hidden.count, privacy: .public) hidden, \(self.freeRooms().count, privacy: .public) with free time")
    }

    /// Publishes the day's bookings for the widget to read.
    ///
    /// Only for today, and only when there is something to say: a widget
    /// showing "free now" from yesterday's bookings would be confidently
    /// wrong, and the snapshot's own day check is the second line of defence,
    /// not the first.
    ///
    /// Stored per campus rather than per account: rooms are not personal, and
    /// keying them to a matricola would mean re-fetching 150 rooms on a career
    /// switch for identical data.
    private func saveWidgetSnapshot() {
        guard let campus, Calendar.current.isDateInToday(day), !rooms.isEmpty
        else { return }

        let snapshot = FreeRoomsSnapshot(
            day: day,
            campus: campus,
            rooms: rooms.map { room in
                FreeRoomsSnapshot.Room(
                    id: room.id,
                    name: room.name,
                    building: room.building,
                    seats: room.seats,
                    busy: room.bookings
                        .map { .init(start: $0.start, end: max($0.start, $0.end)) }
                        .sorted { $0.start < $1.start })
            })
        OfflineStore.shared.save(
            snapshot, as: FreeRoomsSnapshot.cacheName, account: campus)
        FreeRoomsSnapshot.knownCampuses = catalogue.campuses
        FreeRoomsSnapshot.lastCampus = campus
        WidgetReloader.request([.freeRooms])
    }

    /// Fetches today's rooms when a widget on the Home Screen would otherwise
    /// have nothing to show.
    ///
    /// The snapshot is written only by a load, and a load used to happen only
    /// on the Aule libere screen — so a student who never opened it that day
    /// had a widget saying "apri l'app" however often they opened the app.
    /// Asks WidgetKit whether the widget is installed first: without one, 150
    /// requests on every foregrounding would be spent on nothing.
    func refreshForWidgetIfNeeded() async {
        guard Calendar.current.isDateInToday(day) else { return }
        let installed = (try? await WidgetCenter.shared.currentConfigurations())?
            .contains { $0.kind == WidgetKind.freeRooms.rawValue } ?? false
        guard installed else { return }
        if let campus = FreeRoomsSnapshot.lastCampus ?? campus,
           let cached = OfflineStore.shared.load(
               FreeRoomsSnapshot.self, as: FreeRoomsSnapshot.cacheName, account: campus),
           cached.value.covers(.now) {
            return
        }
        await load()
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

    /// Static and parameterised so it carries no actor-isolated state and can
    /// run concurrently off the main actor. The request itself is shared with
    /// the widget, in ``RoomOccupancy``.
    private static func occupancy(
        occupancyID id: String, roomID: String, day: Date, session: URLSession
    ) async -> [RoomBooking]? {
        guard case .busy(let bands) = await RoomOccupancy.fetch(
            occupancyID: id, on: day, session: session)
        else { return nil }
        return bands.enumerated().map { index, band in
            RoomBooking(id: "\(roomID)-\(index)", start: band.start, end: band.end, title: nil)
        }
    }

    /// Hands the widget the rooms it needs to fetch a campus by itself.
    ///
    /// Every campus, not only the one on screen: the widget can be configured
    /// for any of them, and the catalogue is already in memory.
    private func publishWidgetCatalogue() {
        guard !publishedCatalogue, !catalogue.rooms.isEmpty else { return }
        publishedCatalogue = true
        let refs = Dictionary(grouping: catalogue.rooms.compactMap { room -> (String, FreeRoomsSnapshot.RoomRef)? in
            guard let campus = room.campusName, let occupancyID = room.occupancyID else { return nil }
            return (campus, .init(id: room.id, name: room.id, building: room.buildingName,
                                  seats: room.capacity > 0 ? room.capacity : nil,
                                  occupancyID: occupancyID))
        }, by: \.0)
        for (campus, pairs) in refs {
            OfflineStore.shared.save(pairs.map(\.1), as: FreeRoomsSnapshot.catalogueCacheName, account: campus)
        }
        FreeRoomsSnapshot.knownCampuses = catalogue.campuses
    }
}

extension OccupancyBand {
    func toBooking(roomID: String, on day: Date, index: Int) -> RoomBooking? {
        interval(on: day).map {
            RoomBooking(id: "\(roomID)-\(index)", start: $0.start, end: $0.end, title: nil)
        }
    }
}
