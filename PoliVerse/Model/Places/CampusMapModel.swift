import Foundation
import MapKit
import Observation
import OSLog

/// Buildings placed on the map, with how busy each one is.
///
/// Coordinates come from the public geojson; room counts from the catalogue;
/// free counts, when asked for, from ``FreeRoomsModel``. Nothing here needs
/// a token.
///
/// The map deliberately shows **buildings, not rooms**. There are 353 rooms and
/// no geometry finer than a building's bounding box, so a room pin would be a
/// building pin wearing a room's name.
@Observable
final class CampusMapModel {
    /// The pins the map is drawing. Grows a few at a time while a placement
    /// is being revealed, so buildings land on the map instead of the whole
    /// campus blinking into place at once.
    private(set) var pins: [MapPin] = []
    /// Every pin the last placement produced, revealed or not. The camera
    /// frames these, so it frames the campus rather than the first batch.
    private(set) var placed: [MapPin] = []
    /// True while pins are still arriving, for the status line.
    private(set) var isPlacing = false
    /// `true` while a load is in flight.
    private(set) var isLoading = false
    /// The last load's error, or `nil` when it succeeded. Only set when there are no
    /// cached coordinates to fall back on.
    private(set) var errorMessage: String?
    /// Whether pins are coloured by availability. Off until occupancy has been
    /// fetched, since a grey map is honest and a green one would not be.
    private(set) var showsAvailability = false

    /// Supplies the rooms per building, and the campus list.
    private let catalogue: any RoomCatalogue
    /// Supplies the occupancy ``loadAvailability(campus:)`` colours the pins with.
    private let freeRooms: any RoomAvailability
    /// The transport the building geojson is fetched through.
    private let http: any HTTP
    /// Diagnostic log for this type, under the `map` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "map")

    /// Building coordinates by building code. Served from the cache first and refreshed
    /// once per launch, since buildings do not move.
    private var locations: [String: BuildingLocation] = [:]

    /// Seeds the pins and stops the model fetching, for previews.
    ///
    /// - Parameters:
    ///   - catalogue: Supplies the rooms per building.
    ///   - freeRooms: Supplies occupancy.
    ///   - pins: The pins to draw.
    convenience init(catalogue: any RoomCatalogue, freeRooms: any RoomAvailability, preview pins: [MapPin]) {
        self.init(catalogue: catalogue, freeRooms: freeRooms)
        self.pins = pins
        self.placed = pins
        self.skipsLoading = true
    }

    /// Set by the preview initialiser; makes ``load(campus:)`` do nothing.
    private var skipsLoading = false

    /// Creates the model without fetching anything.
    ///
    /// - Parameters:
    ///   - catalogue: Supplies the rooms per building, and the campus list.
    ///   - freeRooms: Supplies occupancy.
    ///   - http: The transport the geojson is fetched through.
    init(catalogue: any RoomCatalogue, freeRooms: any RoomAvailability, http: any HTTP = PublicHTTP()) {
        self.catalogue = catalogue
        self.freeRooms = freeRooms
        self.http = http
    }

    /// The campuses the catalogue knows.
    var campuses: [String] { catalogue.campuses }

    /// A region around whatever is currently pinned.
    ///
    /// Takes no campus: ``pins`` is already only that campus's buildings, and
    /// an argument here would invite the two to disagree.
    var region: MKCoordinateRegion? {
        BuildingLocation.region(covering: placed.map {
            BuildingLocation(id: $0.id, coordinate: $0.coordinate)
        })
    }

    /// The rooms in one building, for the sheet a pin opens.
    ///
    /// - Parameter buildingCode: The building's `csie`.
    /// - Returns: The rooms, sorted by code.
    func rooms(in buildingCode: String) -> [Classroom] {
        catalogue.rooms.filter { $0.buildingCode == buildingCode }
            .sorted { $0.id < $1.id }
    }

    /// Places the campus's buildings on the map.
    ///
    /// Pins appear as soon as anything can place them: the cached coordinates and cached
    /// catalogue first, then again as fresh coordinates and a fresh catalogue arrive. The
    /// geojson is refetched once per launch.
    ///
    /// Availability is not loaded — see ``loadAvailability(campus:)``.
    ///
    /// - Parameter campus: The campus to show, or `nil` for every campus.
    func load(campus: String?) async {
        guard !skipsLoading else { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        showsAvailability = false

        if locations.isEmpty, let cached = await MapPlacement.cachedLocations() {
            locations = cached
        }
        await place(campus: campus)

        async let catalogueLoaded: Void = catalogue.load()
        if !locationsRefreshed {
            await loadLocations()
            await place(campus: campus)
        }
        await catalogueLoaded
        await place(campus: campus)
        log.notice("map: \(self.placed.count, privacy: .public) buildings placed")
    }

    /// Recomputes the pins for a campus and starts revealing them.
    ///
    /// Does nothing before both coordinates and a catalogue are held, or when the
    /// placement is unchanged. A new placement drops any colouring, since a legend over
    /// grey pins would claim more than it knows. The reveal is not awaited, so
    /// ``load(campus:)`` can keep fetching while pins land.
    ///
    /// - Parameter campus: The campus to place, or `nil` for every campus.
    private func place(campus: String?) async {
        guard !locations.isEmpty, !catalogue.rooms.isEmpty else { return }
        let placed = await MapPlacement.pinsInBackground(
            rooms: catalogue.rooms, locations: locations, campus: campus)
        guard placed != self.placed.map(\.uncoloured) else { return }
        self.placed = placed
        // Placing again drops any colouring, so say so rather than keep a
        // legend over grey pins.
        showsAvailability = false
        // Not awaited: the reveal paces itself over a few hundred milliseconds
        // and ``load(campus:)`` has more fetching to do meanwhile.
        revealTask?.cancel()
        revealTask = Task { await reveal(placed) }
    }

    /// The reveal currently running, cancelled when a new placement supersedes it.
    private var revealTask: Task<Void, Never>?

    /// How many pins land together during a reveal. Small enough that a campus visibly
    /// fills in, and brief enough that a whole campus is placed inside half a second.
    private static let batchSize = 4
    /// How long between batches during a reveal.
    private static let batchDelay = Duration.milliseconds(60)

    /// Hands the map its pins a batch at a time.
    ///
    /// Pins already on screen keep their place: only what is new is added, so a second
    /// placement tops the map up instead of clearing it and starting again. A reveal
    /// superseded by a newer placement stops rather than interleaving with it.
    ///
    /// - Parameter placed: The full placement to reveal.
    private func reveal(_ placed: [MapPin]) async {
        revealID += 1
        let id = revealID
        // Anything already shown that survived this placement stays put.
        let shownIDs = Set(pins.map(\.id))
        var shown = placed.filter { shownIDs.contains($0.id) }
        let arriving = placed.filter { !shownIDs.contains($0.id) }
        pins = shown
        guard !arriving.isEmpty else { return }

        isPlacing = true
        defer { if revealID == id { isPlacing = false } }
        for batch in stride(from: 0, to: arriving.count, by: Self.batchSize) {
            if batch > 0 {
                try? await Task.sleep(for: Self.batchDelay)
                // A newer placement is revealing; leave it to it.
                guard revealID == id else { return }
            }
            shown.append(contentsOf: arriving[batch..<min(batch + Self.batchSize, arriving.count)])
            pins = shown
        }
    }

    /// Identifies the reveal in flight, so a placement arriving mid-reveal supersedes the
    /// previous one.
    private var revealID = 0

    /// Whether this launch has refetched the geojson. Cached coordinates are shown first
    /// and refreshed once.
    private var locationsRefreshed = false

    /// Colours the pins by how many of each building's rooms are free right now.
    ///
    /// Never automatic: this is one request per room, so it happens only when the student
    /// asks. The occupancy service is pointed at the campus on screen first — without
    /// that it keeps whichever campus the Aule libere screen last used, and every pin
    /// would silently fall back to unknown.
    ///
    /// Only rooms the occupancy pass answered for are counted.
    ///
    /// - Parameter campus: The campus on screen.
    func loadAvailability(campus: String?) async {
        guard !placed.isEmpty else { return }
        // Point the occupancy service at the campus on screen first. Without
        // this it keeps whichever campus the Aule libere screen last used, and
        // the pins get coloured from a different city's rooms — every pin
        // would fall back to "unknown", silently.
        if freeRooms.campus != campus, campus != nil {
            freeRooms.campus = campus
        }
        await freeRooms.load()
        let free = Set(freeRooms.freeNow().map(\.id))
        guard !free.isEmpty || !freeRooms.rooms.isEmpty else { return }

        placed = await MapPlacement.colouredInBackground(
            placed, rooms: catalogue.rooms, covered: Set(freeRooms.rooms.map(\.id)), free: free)
        let shownIDs = Set(pins.map(\.id))
        pins = placed.filter { shownIDs.contains($0.id) }
        showsAvailability = true
    }

    /// Fetches the building coordinates from the public geojson and caches them.
    ///
    /// The empty `filter` parameter is required: without it the service answers 400
    /// rather than everything. A failure is only reported when there are no cached
    /// coordinates to place pins with.
    private func loadLocations() async {
        do {
            // The empty `filter` is required: without the parameter the
            // service answers 400 rather than "everything".
            let data = try await http.data(for: APIRequest(
                host: .maps, path: "/spazi/edificio/geojson",
                query: [.init(name: "filter", value: "")], authenticated: false))
            let decoded = try await BackgroundJSON.decode(BuildingGeoJSON.self, from: data)
            locations = Dictionary(
                decoded.locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            locationsRefreshed = true
            await MapPlacement.cache(locations)
            log.notice("map: \(self.locations.count, privacy: .public) building coordinates")
        } catch {
            log.error("Building coordinates failed: \(error.localizedDescription)")
            // Cached coordinates still place the pins; only say so when
            // there is nothing to show.
            if locations.isEmpty { errorMessage = userFacingMessage(error) }
        }
    }
}
