import CoreLocation
import Foundation
import Testing
@testable import PoliVerse

/// Placing pins is pure and runs off the main thread, so the map can open
/// first and fill in as the catalogue and coordinates arrive.
@Suite("Map placement")
struct MapPlacementTests {
    private func room(_ id: String, _ building: String, campus: String = "Leonardo") -> Classroom {
        var room = Classroom(id: id, capacity: 10, buildingCode: building, floorCode: "")
        room.buildingName = "Edificio \(building)"
        room.campusName = campus
        return room
    }

    private func location(_ id: String) -> BuildingLocation {
        BuildingLocation(id: id, coordinate: CLLocationCoordinate2D(latitude: 45.47, longitude: 9.22))
    }

    @Test("A pin per building that has rooms and a coordinate, sorted by name")
    func pins() {
        let rooms = [room("1", "B"), room("2", "B"), room("3", "A"), room("4", "C")]
        let placed = MapPlacement.pins(rooms: rooms, locations: ["A": location("A"), "B": location("B")], campus: nil)
        #expect(placed.map(\.id) == ["A", "B"])
        #expect(placed.map(\.totalRooms) == [1, 2])
        #expect(placed.allSatisfy { $0.freeRooms == nil })
    }

    @Test("Only the chosen campus is placed")
    func campus() {
        let rooms = [room("1", "A"), room("2", "B", campus: "Bovisa")]
        let placed = MapPlacement.pins(rooms: rooms, locations: ["A": location("A"), "B": location("B")], campus: "Bovisa")
        #expect(placed.map(\.id) == ["B"])
    }

    @Test("Availability counts only rooms the occupancy pass covered")
    func availability() {
        let rooms = [room("1", "A"), room("2", "A"), room("3", "A")]
        let pins = MapPlacement.pins(rooms: rooms, locations: ["A": location("A")], campus: nil)
        let coloured = MapPlacement.coloured(pins, rooms: rooms, covered: ["1", "2"], free: ["2"])
        #expect(coloured[0].freeRooms == 1)
        #expect(coloured[0].totalRooms == 2)
    }

    @Test("A building nobody checked keeps its uncoloured pin")
    func uncovered() {
        let rooms = [room("1", "A")]
        let pins = MapPlacement.pins(rooms: rooms, locations: ["A": location("A")], campus: nil)
        #expect(MapPlacement.coloured(pins, rooms: rooms, covered: [], free: []) == pins)
    }

    @Test("Coordinates survive the disk cache")
    func cacheRoundTrip() throws {
        let stored = MapPlacement.Stored(location("MIA0102"))
        let data = try JSONEncoder().encode([stored])
        let decoded = try JSONDecoder().decode([MapPlacement.Stored].self, from: data)
        #expect(decoded.first?.location.id == "MIA0102")
        #expect(decoded.first?.location.coordinate.latitude == 45.47)
    }
}
