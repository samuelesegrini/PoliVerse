import Foundation
import WidgetKit
import Observation
import OSLog

/// Which rooms are free, and when.
///
/// Built on the maps service's public occupancy endpoint,
/// `GET /ricerca/aula/occupazione/{idaula}/{yyyy-MM-dd}`, which answers the booked
/// bands for one room on one day and needs no token. Rooms the university does not
/// publish answer `MSG_OCCUPAZIONI_NASCOSTE`; those are reported in ``hiddenRooms``
/// rather than guessed at.
///
/// The bookings service `ws_aule`, which the official client uses, is closed to
/// student accounts: its own profile answers “Utente non abilitato” and the account's
/// own answers “Scope OAuth non valido”.
///
/// ## Cost
///
/// Occupancy is per room, so a campus is one request each — up to around 158 for the
/// largest. They run through a ``ResourceLoader`` in batches of ``concurrency``, are
/// cached per room and day, and are shared with the room detail screen, so a room
/// already fetched costs nothing.
///
/// ## Freshness
///
/// The load window is one minute rather than the usual five, because occupancy turns
/// over on the lecture boundary and this is the screen where stale data means walking
/// across campus to an occupied room.
@Observable
final class FreeRoomsModel {
    /// The rooms of the chosen campus, with their bookings for ``day``. Rooms that could
    /// not be asked about are absent.
    private(set) var rooms: [RoomSchedule] = []
    /// `true` while a pass is in flight.
    private(set) var isLoading = false
    /// The last pass's error, or `nil` when it succeeded.
    private(set) var errorMessage: String?
    /// Rooms whose occupancy could not be read — hidden by the university, or the request
    /// failed.
    ///
    /// Named rather than silently dropped: not being able to tell is not the same as the
    /// room being free.
    private(set) var hiddenRooms: [String] = []
    /// How far through the pass the fetch has got, for a screen that takes a moment.
    private(set) var progress: (done: Int, total: Int) = (0, 0)
    /// When the occupancy on screen was fetched, or `nil` if it never was.
    ///
    /// Not persisted: occupancy is never restored from disk here, so the only age worth
    /// reporting is the one since this session's pass.
    private(set) var loadedAt: Date?

    /// The day being shown.
    var day: Date = .now
    /// The campus being shown. Set to the student's ``FavouriteCampus``, or else the
    /// catalogue's first campus, on the first load when nothing has been chosen.
    var campus: String?

    /// Supplies the rooms to ask about, and the campus list.
    private let catalogue: any RoomCatalogue
    /// The session the occupancy requests are issued through.
    private let session: URLSession
    /// Diagnostic log for this type, under the `aule` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "aule")

    /// Suppresses repeated passes within a minute, keyed on the day and campus being
    /// shown.
    private var window = LoadWindow(interval: 60)

    /// Fetches, caches and coalesces occupancy per room and day.
    ///
    /// Coalescing is what stops a room opened from search being fetched twice while the
    /// campus pass is still running.
    private let loader: ResourceLoader<OccupancyKey, [RoomBooking]>

    /// One room on one day, which is what occupancy is cached by.
    nonisolated struct OccupancyKey: Hashable, Sendable {
        /// The room's printed code, which the bookings are identified by.
        let roomID: String
        /// The room's `idaula`, which the endpoint takes.
        let occupancyID: String
        /// The day, as `yyyy-MM-dd`.
        let day: String
    }

    /// How many occupancy requests run at once. Firing a whole campus at a public service
    /// at once is both rude and slower.
    private let concurrency = 8

    /// Seeds the rooms and stops the model fetching, for previews.
    ///
    /// - Parameters:
    ///   - catalogue: Supplies the campus list.
    ///   - rooms: The rooms to report.
    convenience init(catalogue: any RoomCatalogue, preview rooms: [RoomSchedule]) {
        self.init(catalogue: catalogue)
        self.rooms = rooms
        self.skipsLoading = true
    }

    /// Set by the preview initialiser; makes ``load(force:)`` do nothing.
    private var skipsLoading = false
    /// Whether the widget's per-campus room list has been written this launch. The
    /// catalogue barely changes, and writing it on every load would rewrite a file per
    /// campus each time.
    private var publishedCatalogue = false

    /// Builds the loader, with half an hour's lifetime per room and day.
    ///
    /// - Parameters:
    ///   - catalogue: Supplies the rooms to ask about.
    ///   - session: The session the occupancy requests are issued through.
    init(catalogue: any RoomCatalogue, session: URLSession = .shared) {
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

    /// The campuses the catalogue knows.
    var campuses: [String] { catalogue.campuses }

    /// Seconds since the occupancy was fetched, for ``FreshnessBar``.
    ///
    /// Computed from ``loadedAt`` rather than stored, so each render reads the current
    /// answer. Nothing ticks, so the value only changes when the view redraws for some
    /// other reason — which is enough for a bar that stays silent under fifteen minutes.
    ///
    /// - Parameter now: The moment to measure from.
    /// - Returns: The age, or `nil` when nothing has been fetched.
    func age(now: Date = .now) -> TimeInterval? {
        loadedAt.map { now.timeIntervalSince($0) }
    }

    /// ``age(now:)`` against the current moment.
    var age: TimeInterval? { age(now: .now) }

    /// Records a pass that produced rooms, and marks the load window for this day and
    /// campus.
    ///
    /// - Parameter date: When the pass completed.
    func markLoaded(at date: Date = .now) {
        loadedAt = date
        window.markLoaded(source: "\(PoliMiDate.queryString(day))|\(campus ?? "-")", at: date)
    }

    /// 08:00 to 20:00 in Rome on ``day``.
    ///
    /// Free time is only reported within it: outside those hours every room is trivially
    /// free, which is true and useless because the building is shut.
    var teachingDay: DateInterval {
        let start = PoliMiDate.time(8, on: day)
        let end = PoliMiDate.time(20, on: day)
        return DateInterval(start: start, end: max(start, end))
    }

    /// Rooms with free time during ``teachingDay``, and when.
    ///
    /// - Parameter minimumMinutes: The shortest gap worth reporting.
    /// - Returns: The rooms with at least one such gap, most free time first, ties broken
    ///   by name.
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

    /// Rooms free for the next half hour, which is the question someone looking for
    /// somewhere to sit is asking.
    ///
    /// - Returns: The free rooms, by name. Empty outside ``teachingDay``.
    func freeNow() -> [RoomSchedule] {
        let now = Date.now
        guard teachingDay.contains(now) else { return [] }
        let window = DateInterval(
            start: now, end: min(now.addingTimeInterval(1800), teachingDay.end))
        return rooms.filter { $0.isFree(during: window) }.sorted { $0.name < $1.name }
    }

    /// Fetches the chosen campus's occupancy for ``day``.
    ///
    /// Loads the catalogue first, chooses a campus if none is set, and publishes the
    /// widget's room list once per launch. Returns without fetching when a pass is in
    /// flight or the one-minute window has not expired for this day and campus.
    ///
    /// Rooms are fetched in batches of ``concurrency`` through the shared loader. A room
    /// whose occupancy is hidden or whose request failed goes to ``hiddenRooms`` rather
    /// than being listed as free. Only a pass that produced rooms marks the window, so a
    /// campus where everything failed is retried rather than reported as fresh and empty.
    ///
    /// - Parameter force: Bypasses the load window.
    func load(force: Bool = false) async {
        guard !skipsLoading else { return }
        await catalogue.load()
        if campus == nil { campus = FavouriteCampus.resolve(FavouriteCampus.stored, among: catalogue.campuses) }
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

    /// Publishes the day's bookings for the free-rooms widget.
    ///
    /// Only for today and only when there is something to say, since a widget showing
    /// “free now” from another day's bookings would be confidently wrong.
    ///
    /// Stored per campus rather than per account: rooms are not personal, and keying them
    /// to a matricola would mean refetching a whole campus on a career switch for
    /// identical data.
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

    /// Fetches today's rooms when the widget would otherwise have nothing to show.
    ///
    /// The snapshot is written only by a load, which happens on the Aule libere screen —
    /// so a student who never opens it would see a widget asking them to open the app.
    /// WidgetKit is asked whether the widget is installed first, so a whole campus is not
    /// fetched on every foregrounding for nothing, and a snapshot already covering today
    /// is left alone.
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

    /// One room's bookings for ``day``.
    ///
    /// Serves the room detail screen, which must not pay for the campus-wide pass. Shares
    /// the same per-room cache, so a room already seen costs nothing.
    ///
    /// - Parameter room: The room to ask about.
    /// - Returns: The bookings, or `nil` when the room has no `idaula`, its occupancy is
    ///   hidden, or the call failed — none of which the caller may render as free.
    func bookings(for room: Classroom) async -> [RoomBooking]? {
        guard let occupancyID = room.occupancyID else { return nil }
        let key = OccupancyKey(
            roomID: room.id, occupancyID: occupancyID,
            day: PoliMiDate.queryString(day))
        return await loader.value(for: key)
    }

    /// Warms the rooms around the one being looked at.
    ///
    /// Detached at background priority and never awaited, so the room the student actually
    /// opened does not wait on its neighbours.
    ///
    /// - Parameter rooms: The rooms to warm.
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

    /// Fetches one room's bookings for a day.
    ///
    /// Static and fully parameterised, so it carries no actor-isolated state and runs off
    /// the main actor. The request itself is shared with the widget, in
    /// ``RoomOccupancy``.
    ///
    /// - Parameters:
    ///   - id: The room's `idaula`.
    ///   - roomID: The room's printed code, which the bookings are identified by.
    ///   - day: The day to ask about.
    ///   - session: The session to fetch through.
    /// - Returns: The bookings, or `nil` when the occupancy is hidden or the call failed.
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

    /// Hands the widget the room references it needs to fetch a campus by itself.
    ///
    /// Every campus, not only the one on screen: the widget can be configured for any of
    /// them, and the catalogue is already in memory. Runs once per launch.
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

/// Turning a busy band into a ``RoomBooking``.
extension OccupancyBand {
    /// Resolves the band against a day and wraps it as a booking.
    ///
    /// - Parameters:
    ///   - roomID: The room the band belongs to.
    ///   - day: The day the times belong to.
    ///   - index: The band's position within the room, which makes the booking's id
    ///     unique.
    /// - Returns: The booking, or `nil` when either time is unparseable.
    func toBooking(roomID: String, on day: Date, index: Int) -> RoomBooking? {
        interval(on: day).map {
            RoomBooking(id: "\(roomID)-\(index)", start: $0.start, end: $0.end, title: nil)
        }
    }
}
/// ``FreeRoomsModel`` satisfies ``RoomAvailability`` as it stands.
///
/// Declared here rather than beside the protocol: ``RoomAvailability`` refines
/// `Sendable`, and a `Sendable` conformance stated in another file is
/// retroactive.
extension FreeRoomsModel: RoomAvailability {}
