import CoreLocation
import Foundation
import MapKit

/// Where a building actually is.
///
/// - Important: taken from the **bbox in the feature's properties**, never from
///   its polygon. The public geojson's outlines are not building footprints:
///   of 465 building features, 142 "detailed" polygons are generated ellipses
///   and 155 are axis-aligned boxes. Drawing them produces a map that looks
///   wrong because it is wrong. The coordinates, on the other hand, are real —
///   so the app pins them onto MapKit's own map and invents nothing.
nonisolated struct BuildingLocation: Identifiable, Sendable, Hashable {
    /// `csie`, the same key the room catalogue uses.
    let id: String
    let coordinate: CLLocationCoordinate2D

    /// A region containing every location, padded so nothing sits on the edge.
    static func region(covering locations: [BuildingLocation]) -> MKCoordinateRegion? {
        guard !locations.isEmpty else { return nil }
        let lats = locations.map(\.coordinate.latitude)
        let lons = locations.map(\.coordinate.longitude)
        let (minLat, maxLat) = (lats.min()!, lats.max()!)
        let (minLon, maxLon) = (lons.min()!, lons.max()!)

        // A single building spans nothing, and MapKit reads a zero span as
        // "zoom to the roof". The floor keeps a lone pin in its context.
        let padding = 1.4
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * padding, 0.004),
                longitudeDelta: max((maxLon - minLon) * padding, 0.004)))
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable, @retroactive Hashable {
    // `nonisolated` on both: this file's types are, and a main-actor operator
    // cannot be called from them.
    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

/// `GET /spazi/edificio/geojson?filter=`
///
/// - Note: `filter` must be present and **empty**. Omitting it answers 500,
///   and so does any value — the parameter exists to be blank.
nonisolated struct BuildingGeoJSON: Decodable, Sendable {
    let features: [Feature]

    nonisolated struct Feature: Decodable, Sendable {
        let properties: Properties?
    }

    nonisolated struct Properties: Decodable, Sendable {
        let POLIMI_ID_SPAZIO: String?
        let SWLAT: Double?
        let SWLNG: Double?
        let NELAT: Double?
        let NELNG: Double?
    }

    var locations: [BuildingLocation] {
        features.compactMap { feature in
            guard
                let p = feature.properties,
                let id = p.POLIMI_ID_SPAZIO, !id.isEmpty,
                let swLat = p.SWLAT, let swLng = p.SWLNG,
                let neLat = p.NELAT, let neLng = p.NELNG
            else { return nil }

            let latitude = (swLat + neLat) / 2
            let longitude = (swLng + neLng) / 2
            // Null Island is a valid coordinate, so a zeroed bbox has to be
            // rejected by hand or every malformed row lands in the Atlantic.
            guard latitude != 0 || longitude != 0 else { return nil }

            return BuildingLocation(
                id: id,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }
}

/// A building on the map, with what is known about how busy it is.
nonisolated struct MapPin: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    /// Nil until occupancy has been fetched. Distinct from zero: "not asked"
    /// and "nothing free" must not look the same, or a map that is still
    /// loading reads as a campus with no space anywhere.
    let freeRooms: Int?
    let totalRooms: Int

    nonisolated enum Availability: Sendable {
        case many, some, few, unknown
    }

    var availability: Availability {
        guard let freeRooms, totalRooms > 0 else { return .unknown }
        let ratio = Double(freeRooms) / Double(totalRooms)
        if ratio > 0.6 { return .many }
        if ratio > 0.3 { return .some }
        return .few
    }

    var label: String {
        guard let freeRooms, totalRooms > 0 else { return "\(totalRooms) aule" }
        return "\(freeRooms)/\(totalRooms) libere"
    }
}
