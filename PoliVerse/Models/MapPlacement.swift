import CoreLocation
import Foundation

extension MapPin {
    /// The pin before availability was counted.
    nonisolated var uncoloured: MapPin {
        MapPin(id: id, name: name, coordinate: coordinate, freeRooms: nil, totalRooms: totalRooms)
    }
}

/// Where the map's pins go, worked out away from the main thread.
///
/// Pure, so ``CampusMapService`` can call it every time something arrives —
/// cached coordinates, the catalogue, fresh coordinates — and the map fills
/// in as data lands instead of waiting for all of it.
nonisolated enum MapPlacement {
    /// One pin per building with rooms and a place to be: a pin for a building
    /// with nothing in it is a pin the user cannot act on.
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

    /// Pins coloured by free rooms. Only rooms the occupancy pass actually
    /// covered are counted; anything else stays out of both halves of the
    /// fraction. Indexed first: filtering every room for every pin was
    /// quadratic on a 350-room catalogue.
    static func coloured(_ pins: [MapPin], rooms: [Classroom], covered: Set<String>, free: Set<String>) -> [MapPin] {
        let byBuilding = Dictionary(grouping: rooms.lazy.filter { covered.contains($0.id) }, by: \.buildingCode)
        return pins.map { pin in
            guard let known = byBuilding[pin.id], !known.isEmpty else { return pin }
            return MapPin(id: pin.id, name: pin.name, coordinate: pin.coordinate,
                          freeRooms: known.count { free.contains($0.id) }, totalRooms: known.count)
        }
    }

    @concurrent
    static func pinsInBackground(rooms: [Classroom], locations: [String: BuildingLocation],
                                 campus: String?) async -> [MapPin] {
        pins(rooms: rooms, locations: locations, campus: campus)
    }

    /// A coordinate as it is written to disk. Buildings do not move, so the
    /// 270 KB geojson need not be fetched before the first pin.
    struct Stored: Codable, Sendable {
        let id: String
        let latitude: Double
        let longitude: Double

        init(_ location: BuildingLocation) {
            id = location.id
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
        }

        var location: BuildingLocation {
            BuildingLocation(id: id, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }

    static let cacheName = "building-locations"

    @concurrent
    static func cachedLocations() async -> [String: BuildingLocation]? {
        guard let entry = DiskCache.load([Stored].self, as: cacheName), !entry.value.isEmpty else { return nil }
        return Dictionary(entry.value.map { ($0.id, $0.location) }, uniquingKeysWith: { first, _ in first })
    }

    @concurrent
    static func cache(_ locations: [String: BuildingLocation]) async {
        DiskCache.save(locations.values.map(Stored.init), as: cacheName)
    }
}
