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

    func load(campus: String?) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await catalogue.load()
        if locations.isEmpty { await loadLocations() }

        let rooms = catalogue.rooms(matching: "", campus: campus)
        // Only buildings that have rooms and a place to be: a pin for a
        // building with nothing in it is a pin the user cannot act on.
        let grouped = Dictionary(grouping: rooms, by: \.buildingCode)
        pins = grouped.compactMap { code, rooms -> MapPin? in
            guard let location = locations[code] else { return nil }
            return MapPin(
                id: code,
                name: rooms.first?.buildingName ?? code,
                coordinate: location.coordinate,
                freeRooms: nil,
                totalRooms: rooms.count)
        }.sorted { $0.name < $1.name }

        showsAvailability = false
        log.notice("map: \(self.pins.count, privacy: .public) buildings placed of \(grouped.count, privacy: .public) with rooms")
    }

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

        pins = pins.map { pin in
            let rooms = rooms(in: pin.id)
            // Only rooms the occupancy pass actually covered can be counted;
            // anything else stays out of both halves of the fraction.
            let known = rooms.filter { room in
                freeRooms.rooms.contains { $0.id == room.id }
            }
            guard !known.isEmpty else { return pin }
            return MapPin(
                id: pin.id, name: pin.name, coordinate: pin.coordinate,
                freeRooms: known.filter { free.contains($0.id) }.count,
                totalRooms: known.count)
        }
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
            let decoded = try JSONDecoder().decode(BuildingGeoJSON.self, from: data)
            locations = Dictionary(
                decoded.locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            log.notice("map: \(self.locations.count, privacy: .public) building coordinates")
        } catch {
            log.error("Building coordinates failed: \(error.localizedDescription)")
            errorMessage = userFacingMessage(error)
        }
    }
}
