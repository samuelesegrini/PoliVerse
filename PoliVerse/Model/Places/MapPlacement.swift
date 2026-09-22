import CoreLocation
import Foundation
import MapKit

/// Dropping the availability a pin was coloured with.
extension MapPin {
    /// The same pin with ``MapPin/freeRooms`` cleared, so it reads as not yet counted
    /// rather than as having nothing free.
    nonisolated var uncoloured: MapPin {
        MapPin(id: id, name: name, coordinate: coordinate, freeRooms: nil, totalRooms: totalRooms)
    }
}

/// Works out where the campus map's pins go, and how they are coloured, away from the
/// main thread.
///
/// Pure functions, so ``CampusMapModel`` can call them each time something arrives —
/// cached coordinates, the catalogue, fresh coordinates — and the map fills in as data
/// lands rather than waiting for all of it.
///
/// Also holds the on-disk cache of building coordinates, since buildings do not move
/// and the geojson is large.
nonisolated enum MapPlacement {
    /// One pin per building that has rooms and a known place, sorted by name.
    ///
    /// Buildings with no coordinate are omitted, since a pin nobody can act on is noise.
    ///
    /// - Parameters:
    ///   - rooms: The room catalogue.
    ///   - locations: Building coordinates by building code.
    ///   - campus: The campus to show, or `nil` for every campus.
    /// - Returns: The uncoloured pins.
    static func pins(rooms: [Classroom], locations: [String: BuildingLocation], campus: String?) -> [MapPin] {
        let grouped = Dictionary(grouping: rooms.lazy.filter { campus == nil || $0.campusName == campus },
                                 by: \.buildingCode)
        return grouped.compactMap { code, rooms -> MapPin? in
            guard let location = locations[code] else { return nil }
            return MapPin(id: code, name: rooms.first?.buildingName ?? code,
                          coordinate: location.coordinate, freeRooms: nil, totalRooms: rooms.count)
        }
        .sorted { $0.name < $1.name }
    }

    /// Colours pins by how many of their rooms are free.
    ///
    /// Only rooms the occupancy pass actually covered are counted, so a room that could
    /// not be asked about stays out of both halves of the fraction. Rooms are indexed by
    /// building first, since filtering the whole catalogue per pin is quadratic.
    ///
    /// - Parameters:
    ///   - pins: The pins to colour.
    ///   - rooms: The room catalogue.
    ///   - covered: Rooms the occupancy pass answered for.
    ///   - free: Rooms that are free.
    /// - Returns: The pins, each coloured where its building has covered rooms and left
    ///   unchanged where it has none.
    static func coloured(_ pins: [MapPin], rooms: [Classroom], covered: Set<String>, free: Set<String>) -> [MapPin] {
        let byBuilding = Dictionary(grouping: rooms.lazy.filter { covered.contains($0.id) }, by: \.buildingCode)
        return pins.map { pin in
            guard let known = byBuilding[pin.id], !known.isEmpty else { return pin }
            return MapPin(id: pin.id, name: pin.name, coordinate: pin.coordinate,
                          freeRooms: known.count { free.contains($0.id) }, totalRooms: known.count)
        }
    }

    /// ``coloured(_:rooms:covered:free:)`` on the global executor.
    ///
    /// - Parameters:
    ///   - pins: The pins to colour.
    ///   - rooms: The room catalogue.
    ///   - covered: Rooms the occupancy pass answered for.
    ///   - free: Rooms that are free.
    /// - Returns: The coloured pins.
    @concurrent
    static func colouredInBackground(_ pins: [MapPin], rooms: [Classroom], covered: Set<String>,
                                     free: Set<String>) async -> [MapPin] {
        coloured(pins, rooms: rooms, covered: covered, free: free)
    }

    /// ``pins(rooms:locations:campus:)`` on the global executor.
    ///
    /// - Parameters:
    ///   - rooms: The room catalogue.
    ///   - locations: Building coordinates by building code.
    ///   - campus: The campus to show, or `nil` for every campus.
    /// - Returns: The uncoloured pins.
    @concurrent
    static func pinsInBackground(rooms: [Classroom], locations: [String: BuildingLocation],
                                 campus: String?) async -> [MapPin] {
        pins(rooms: rooms, locations: locations, campus: campus)
    }

    /// A building coordinate as it is written to disk, so the large geojson need not be
    /// fetched before the first pin appears.
    struct Stored: Codable, Sendable {
        /// The building code, `csie`.
        let id: String
        /// The building's latitude.
        let latitude: Double
        /// The building's longitude.
        let longitude: Double

        /// Captures a location for storage.
        ///
        /// - Parameter location: The location to store.
        init(_ location: BuildingLocation) {
            id = location.id
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
        }

        /// The stored coordinate back as a ``BuildingLocation``.
        var location: BuildingLocation {
            BuildingLocation(id: id, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }

    /// The ``DiskCache`` record the coordinates are stored under.
    static let cacheName = "building-locations"

    /// The stored building coordinates, read on the global executor.
    ///
    /// - Returns: The coordinates by building code, or `nil` when nothing usable is
    ///   stored.
    @concurrent
    static func cachedLocations() async -> [String: BuildingLocation]? {
        guard let entry = DiskCache.load([Stored].self, as: cacheName), !entry.value.isEmpty else { return nil }
        return Dictionary(entry.value.map { ($0.id, $0.location) }, uniquingKeysWith: { first, _ in first })
    }

    /// Stores building coordinates, on the global executor.
    ///
    /// - Parameter locations: The coordinates by building code.
    @concurrent
    static func cache(_ locations: [String: BuildingLocation]) async {
        DiskCache.save(locations.values.map(Stored.init), as: cacheName)
    }
}


/// Where the map opens for a campus before its pins are placed, so choosing Como does
/// not show Milano while the catalogue loads.
nonisolated enum CampusRegions {
    /// The satellite campuses, matched on a keyword in the campus name.
    private static let centres: [(keyword: String, latitude: Double, longitude: Double)] = [
        ("bovisa", 45.5030, 9.1560),
        ("como", 45.8013, 9.0935),
        ("lecco", 45.8565, 9.3970),
        ("cremona", 45.1390, 10.0260),
        ("mantova", 45.1570, 10.7930),
        ("piacenza", 45.0440, 9.6960),
    ]

    /// The region to open on for a campus.
    ///
    /// - Parameter campus: The campus name, matched case- and diacritic-insensitively
    ///   against ``centres``.
    /// - Returns: The campus's region, or Milano Città Studi for an unrecognised or
    ///   absent name.
    static func region(for campus: String?) -> MKCoordinateRegion {
        let name = campus?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased() ?? ""
        let centre = centres.first { name.contains($0.keyword) }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centre?.latitude ?? 45.4786, longitude: centre?.longitude ?? 9.2272),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
    }
}
