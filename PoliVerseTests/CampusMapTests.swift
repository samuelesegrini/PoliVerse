import CoreLocation
import Foundation
import MapKit
import Testing
@testable import PoliVerse

/// The map's pure parts: reading coordinates out of the geojson, and deciding
/// what a pin should say.
///
/// The prototype established the constraint these encode: the geojson's
/// polygons are generated ellipses and bounding boxes, not footprints, so only
/// the **bbox in the properties** may be trusted. Everything here works from
/// that and never from the ring.
@Suite("Campus map")
struct CampusMapTests {
    /// A feature exactly as the service sends it, ring included, to prove the
    /// ring is ignored.
    private let feature = """
    {"type":"FeatureCollection","features":[
      {"type":"Feature",
       "geometry":{"type":"Polygon","coordinates":[[[9.2,45.4],[9.3,45.5],[9.2,45.4]]]},
       "properties":{"POLIMI_ID_SPAZIO":"MIA0102","SWLNG":9.2265,"SWLAT":45.4781,
                     "NELNG":9.2285,"NELAT":45.4795}}]}
    """

    private func placed(_ json: String) -> [BuildingLocation] {
        (try? JSONDecoder().decode(BuildingGeoJSON.self, from: Data(json.utf8)))?.locations ?? []
    }

    @Test("A feature yields its building code and the centre of its bbox")
    func centre() {
        let parsed = placed(feature)
        #expect(parsed.count == 1)
        #expect(parsed[0].id == "MIA0102")
        #expect(abs(parsed[0].coordinate.latitude - 45.4788) < 0.0001)
        #expect(abs(parsed[0].coordinate.longitude - 9.2275) < 0.0001)
    }

    /// The ring is a generated ellipse. Using it would put the pin somewhere
    /// the building is not.
    @Test("The polygon ring is ignored entirely")
    func ringIgnored() {
        // The ring's own centre is near 45.43/9.23; the bbox centre is not.
        #expect(placed(feature)[0].coordinate.latitude > 45.47)
    }

    @Test("A feature without a bbox is dropped rather than placed at zero")
    func missingBounds() {
        let json = """
        {"features":[{"properties":{"POLIMI_ID_SPAZIO":"X"}},
                     {"properties":{"POLIMI_ID_SPAZIO":"Y","SWLNG":9.1,"SWLAT":45.4,
                                    "NELNG":9.2,"NELAT":45.5}}]}
        """
        let parsed = placed(json)
        #expect(parsed.map(\.id) == ["Y"])
    }

    @Test("A feature without an id is dropped")
    func missingID() {
        let json = """
        {"features":[{"properties":{"SWLNG":9.1,"SWLAT":45.4,"NELNG":9.2,"NELAT":45.5}}]}
        """
        #expect(placed(json).isEmpty)
    }

    /// Null Island is a real coordinate, so a zeroed bbox has to be rejected
    /// explicitly or every broken row lands off the coast of Africa.
    @Test("A zeroed bbox is rejected")
    func zeroBounds() {
        let json = """
        {"features":[{"properties":{"POLIMI_ID_SPAZIO":"Z","SWLNG":0,"SWLAT":0,
                                    "NELNG":0,"NELAT":0}}]}
        """
        #expect(placed(json).isEmpty)
    }

    @Test("A region spans every building given, with room to breathe")
    func region() {
        let locations = [
            BuildingLocation(id: "A", coordinate: .init(latitude: 45.478, longitude: 9.227)),
            BuildingLocation(id: "B", coordinate: .init(latitude: 45.482, longitude: 9.233)),
        ]
        let region = BuildingLocation.region(covering: locations)
        #expect(region != nil)
        #expect(abs(region!.center.latitude - 45.480) < 0.001)
        // Wider than the raw span, so pins are not glued to the edge.
        #expect(region!.span.latitudeDelta > 0.004)
    }

    @Test("No buildings means no region rather than a default one")
    func emptyRegion() {
        #expect(BuildingLocation.region(covering: []) == nil)
    }

    /// A single building would otherwise produce a zero span, which MapKit
    /// renders as a maximum zoom-in on one roof.
    @Test("One building still gets a usable span")
    func singleBuildingRegion() {
        let region = BuildingLocation.region(covering: [
            BuildingLocation(id: "A", coordinate: .init(latitude: 45.478, longitude: 9.227))])
        #expect((region?.span.latitudeDelta ?? 0) > 0.0005)
    }
}

/// What a pin says about a building.
@Suite("Map pins")
struct MapPinTests {
    private func pin(free: Int, total: Int) -> MapPin {
        MapPin(id: "MIA0102", name: "Edificio 2",
               coordinate: .init(latitude: 45.478, longitude: 9.227),
               freeRooms: free, totalRooms: total)
    }

    @Test("Availability buckets follow the free ratio")
    func buckets() {
        #expect(pin(free: 8, total: 10).availability == .many)
        #expect(pin(free: 4, total: 10).availability == .some)
        #expect(pin(free: 1, total: 10).availability == .few)
    }

    /// Before occupancy has loaded a pin must not claim the building is full;
    /// "nothing free" and "not asked yet" look identical otherwise.
    @Test("Unknown occupancy is its own state, not zero free")
    func unknownIsNotEmpty() {
        let unknown = MapPin(id: "X", name: "X",
                             coordinate: .init(latitude: 45, longitude: 9),
                             freeRooms: nil, totalRooms: 10)
        #expect(unknown.availability == .unknown)
        #expect(unknown.label == "10 aule")
    }

    @Test("A known count is shown as free over total")
    func knownLabel() {
        #expect(pin(free: 3, total: 10).label == "3/10 libere")
    }

    @Test("A building with no rooms is not bucketed as full")
    func noRooms() {
        #expect(pin(free: 0, total: 0).availability == .unknown)
    }
}

/// The floor plan is the one thing only the university has, so the URL that
/// fetches it is worth pinning.
@Suite("Floor plans")
struct FloorPlanTests {
    private let room = Classroom(
        id: "B2.1.9", capacity: 100, buildingCode: "MIB0202",
        floorCode: "MIB0202001", occupancyID: "1890", roomCode: "MIB0202001009")

    @Test("A room's plan highlights that room")
    func roomPlan() {
        #expect(room.floorPlanURL?.absoluteString
            == "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano/MIB0202001/MIB0202001009")
    }

    /// Without the room code there is still a plan of the floor — worth
    /// showing, just without the highlight.
    @Test("Without a room code the plain floor plan is used")
    func floorOnlyPlan() {
        var plain = room
        plain.roomCode = nil
        #expect(plain.floorPlanURL?.absoluteString
            == "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano/MIB0202001")
    }

    @Test("No floor code means no plan rather than a broken URL")
    func noFloor() {
        let room = Classroom(id: "X", capacity: 1, buildingCode: "B", floorCode: "")
        #expect(room.floorPlanURL == nil)
    }
}

/// The day strip in the room detail. Its job is to never make a busy room look
/// free, which is harder than it sounds once bookings overlap.
@Suite("Occupancy timeline")
struct OccupancyTimelineTests {
    private let calendar = PoliMiDate.romeCalendar

    private var day: Date {
        PoliMiDate.romeCalendar.date(
            from: DateComponents(year: 2026, month: 9, day: 11, hour: 12))!
    }

    private var window: DateInterval {
        DateInterval(start: PoliMiDate.time(8, on: day), end: PoliMiDate.time(20, on: day))
    }

    private func booking(_ from: Int, _ to: Int) -> RoomBooking {
        RoomBooking(id: "\(from)", start: PoliMiDate.time(from, on: day),
                    end: PoliMiDate.time(to, on: day), title: nil)
    }

    /// The whole point of the strip: a room booked morning and afternoon must
    /// read as free only in between.
    @Test("Free slots are the gaps the strip leaves green")
    func gapsMatchTheStrip() {
        let schedule = RoomSchedule(
            id: "B2.1.9", name: "B2.1.9", building: nil, seats: nil,
            bookings: [booking(9, 11), booking(14, 16)])
        #expect(schedule.freeSlots(in: window).map(RoomScheduleView.format)
            == ["08:00–09:00", "11:00–14:00", "16:00–20:00"])
    }

    @Test("A booking outside the day does not shift the ones inside it")
    func outsideDay() {
        let schedule = RoomSchedule(
            id: "X", name: "X", building: nil, seats: nil,
            bookings: [booking(6, 9), booking(19, 22)])
        #expect(schedule.freeSlots(in: window).map(RoomScheduleView.format) == ["09:00–19:00"])
    }

    /// Bookings overlap in real data — a lecture and an exam in the same hour.
    /// Drawn end to end they would stretch past the end of the day.
    @Test("Overlapping bookings do not extend the day")
    func overlapping() {
        let schedule = RoomSchedule(
            id: "X", name: "X", building: nil, seats: nil,
            bookings: [booking(9, 13), booking(10, 12)])
        #expect(schedule.freeSlots(in: window).map(RoomScheduleView.format)
            == ["08:00–09:00", "13:00–20:00"])
    }
}
