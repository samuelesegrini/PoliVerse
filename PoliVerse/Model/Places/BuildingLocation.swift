import CoreLocation
import Foundation
import MapKit

/// Where a building is.
///
/// - Important: taken from the bounding box in a geojson feature's properties, never
///   from its polygon. The public geojson's outlines are not building footprints —
///   many are generated ellipses or axis-aligned boxes — so drawing them produces a
///   map that is wrong. The coordinates are real, so the app pins them onto MapKit's
///   own map and invents nothing.
nonisolated struct BuildingLocation: Identifiable, Sendable, Hashable {
    /// The building code, `csie`.
    let id: String
    /// Where the pin goes.
    /// The centre of the building's bounding box.
    let coordinate: CLLocationCoordinate2D

    /// A region containing every given location, padded so nothing sits on the edge.
    ///
    /// The span has a floor, because a single building spans nothing and MapKit reads a
    /// zero span as an instruction to zoom to the roof.
    ///
    /// - Parameter locations: The locations to cover.
    /// - Returns: The region, or `nil` for an empty list.
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

/// Value semantics for a coordinate, so the types that hold one can be `Equatable` and
/// `Hashable`.
///
/// Both members are `nonisolated`, since this file's types are and a main-actor
/// operator could not be called from them.
extension CLLocationCoordinate2D: @retroactive Equatable, @retroactive Hashable {
    // `nonisolated` on both: this file's types are, and a main-actor operator
    // cannot be called from them.
    /// Whether two coordinates have the same latitude and longitude.
    ///
    /// - Parameters:
    ///   - lhs: The first coordinate.
    ///   - rhs: The second.
    /// - Returns: `true` when both components are exactly equal.
    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    /// Hashes the latitude and longitude.
    ///
    /// - Parameter hasher: The hasher to feed.
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

/// The answer to `GET /spazi/edificio/geojson?filter=`.
///
/// - Note: `filter` must be present and empty. Omitting it answers 500, and so does
///   any value.
nonisolated struct BuildingGeoJSON: Decodable, Sendable {
    /// The features, one per building.
    let features: [Feature]

    /// One geojson feature. Only its properties are read; the geometry is not drawn.
    nonisolated struct Feature: Decodable, Sendable {
        /// The feature's properties, which carry the identity and the bounding box.
        let properties: Properties?
    }

    /// A building's identity and the corners of its bounding box.
    nonisolated struct Properties: Decodable, Sendable {
        /// The building code, `csie`.
        let POLIMI_ID_SPAZIO: String?
        /// South-west corner latitude.
        let SWLAT: Double?
        /// South-west corner longitude.
        let SWLNG: Double?
        /// North-east corner latitude.
        let NELAT: Double?
        /// North-east corner longitude.
        let NELNG: Double?
    }

    /// The buildings that carry an identity and a complete bounding box, at the centre of
    /// that box.
    ///
    /// A zeroed box is rejected by hand, since `0, 0` is a valid coordinate in the
    /// Atlantic.
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
    /// The building code, `csie`.
    let id: String
    /// The building's name, falling back to its code.
    let name: String
    /// Where the pin goes.
    let coordinate: CLLocationCoordinate2D
    /// How many of the counted rooms are free, or `nil` before occupancy has been fetched.
    ///
    /// Distinct from zero: a map still loading must not read as a campus with no space
    /// anywhere.
    let freeRooms: Int?
    /// How many rooms the count covers — every room in the building before occupancy, and
    /// only the rooms the pass answered for afterwards.
    let totalRooms: Int

    /// How free a building is, as the pin's colour says it.
    nonisolated enum Availability: Sendable {
        /// `many` above three fifths free, `some` above three tenths, `few` below, and
        /// `unknown` before occupancy has been counted.
        case many, some, few, unknown
    }

    /// How free the building is, or ``Availability/unknown`` before occupancy has been
    /// counted.
    var availability: Availability {
        guard let freeRooms, totalRooms > 0 else { return .unknown }
        let ratio = Double(freeRooms) / Double(totalRooms)
        if ratio > 0.6 { return .many }
        if ratio > 0.3 { return .some }
        return .few
    }

    /// The pin's caption: how many rooms are free of how many counted, or the room count
    /// alone before occupancy has been fetched.
    var label: String {
        guard let freeRooms, totalRooms > 0 else { return "\(totalRooms) aule" }
        return "\(freeRooms)/\(totalRooms) libere"
    }
}
