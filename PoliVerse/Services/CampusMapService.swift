import Foundation
import MapKit
import Observation
import OSLog

/// Buildings placed on the map, with how busy each one is.
///
/// Coordinates come from the public geojson; room counts from the catalogue;
/// free counts, when asked for, from ``FreeRoomsService``. Nothing here needs
/// a token.
///
/// The map deliberately shows **buildings, not rooms**. There are 353 rooms and
/// no geometry finer than a building's bounding box, so a room pin would be a
/// building pin wearing a room's name.
@Observable
final class CampusMapService {
    private(set) var pins: [MapPin] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Whether pins are coloured by availability. Off until occupancy has been
    /// fetched, since a grey map is honest and a green one would not be.
    private(set) var showsAvailability = false

    private let catalogue: RoomsService
    private let freeRooms: FreeRoomsService
    private let session: URLSession
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "map")
    private let url = URL(string:
        "https://onlineservices.polimi.it/maps_rest/rest/spazi/edificio/geojson?filter=")!

    /// Fetched once: buildings do not move.
    private var locations: [String: BuildingLocation] = [:]

    convenience init(catalogue: RoomsService, freeRooms: FreeRoomsService, preview pins: [MapPin]) {
        self.init(catalogue: catalogue, freeRooms: freeRooms)
        self.pins = pins
        self.skipsLoading = true
    }

    private var skipsLoading = false

    init(catalogue: RoomsService, freeRooms: FreeRoomsService, session: URLSession = .shared) {
        self.catalogue = catalogue
        self.freeRooms = freeRooms
        self.session = session
    }

    var campuses: [String] { catalogue.campuses }

    /// A region around whatever is currently pinned.
    ///
    /// Takes no campus: ``pins`` is already only that campus's buildings, and
    /// an argument here would invite the two to disagree.
    var region: MKCoordinateRegion? {
        BuildingLocation.region(covering: pins.map {
            BuildingLocation(id: $0.id, coordinate: $0.coordinate)
        })
    }

    func rooms(in buildingCode: String) -> [Classroom] {
        catalogue.rooms.filter { $0.buildingCode == buildingCode }
            .sorted { $0.id < $1.id }
    }

    /// Pins appear as soon as anything can place them: coordinates cached
    /// from an earlier visit and the cached catalogue first, then again as
    /// fresh coordinates and a fresh catalogue arrive. Before, the map waited
    /// for all four catalogue requests and the geojson before its first pin.
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
        log.notice("map: \(self.pins.count, privacy: .public) buildings placed")
    }

    private func place(campus: String?) async {
        guard !locations.isEmpty, !catalogue.rooms.isEmpty else { return }
        let placed = await MapPlacement.pinsInBackground(
            rooms: catalogue.rooms, locations: locations, campus: campus)
        if placed != pins { pins = placed }
    }

    /// Whether this launch has fetched the geojson; cached coordinates are
    /// shown first but refreshed once per launch.
    private var locationsRefreshed = false

    /// Colours the pins by how many rooms are free right now.
    ///
    /// Separate from ``load(campus:)`` and never automatic: this is one
    /// request per room — around 150 for Milano Leonardo — so it happens when
    /// the user asks for it and not before.
    func loadAvailability(campus: String?) async {
        guard !pins.isEmpty else { return }
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

        pins = MapPlacement.coloured(
            pins, rooms: catalogue.rooms, covered: Set(freeRooms.rooms.map(\.id)), free: free)
        showsAvailability = true
    }

    private func loadLocations() async {
        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 30
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
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
