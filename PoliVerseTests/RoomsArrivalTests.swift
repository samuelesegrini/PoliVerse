import CoreLocation
import Foundation
import MapKit
import Testing
@testable import PoliVerse

/// The order rooms are asked about, the list that stays still while they
/// arrive, and the instants at which "free now" changes.
@Suite("Aule: ordine, arrivo e confini")
struct RoomsOrderTests {
    private func room(_ id: String, _ building: String, campus: String = "Leonardo", code: String? = nil) -> Classroom {
        var room = Classroom(id: id, capacity: 10, buildingCode: building, floorCode: "0")
        room.campusName = campus
        room.roomCode = code
        return room
    }

    private let noon = Date(timeIntervalSince1970: 1_772_000_000)

    private func booking(_ id: String, from start: TimeInterval, to end: TimeInterval) -> RoomBooking {
        RoomBooking(id: id, start: noon.addingTimeInterval(start), end: noon.addingTimeInterval(end), title: nil)
    }

    private func schedule(_ id: String, _ bookings: [RoomBooking]) -> RoomSchedule {
        RoomSchedule(id: id, name: id, building: nil, seats: nil, bookings: bookings)
    }

    @Test("R13: prima gli edifici sulla mappa, poi quello della prossima lezione, poi la sede preferita")
    func test_R13_relevanceOrder() {
        let rooms = [room("a", "X", campus: "Bovisa"), room("b", "L"), room("c", "N"), room("d", "V"), room("e", "L")]
        let ordered = RelevanceOrder.order(rooms, visible: ["V"], nextLecture: "N", favourite: "Leonardo")
        #expect(ordered.map(\.id) == ["d", "c", "b", "e", "a"])
    }

    @Test("R13: senza mappa né lezione l'ordine del catalogo resta com'è")
    func test_R13_orderIsStable() {
        let rooms = [room("c", "A"), room("a", "B"), room("b", "A")]
        #expect(RelevanceOrder.order(rooms, visible: [], nextLecture: nil, favourite: nil).map(\.id) == ["c", "a", "b"])
    }

    @Test("R13: l'edificio della prossima lezione si trova dal nome o dalla sigla dell'aula")
    func test_R13_lectureBuilding() {
        let rooms = [room("B.3.2", "B"), room("N.1.1", "N", code: "CO11")]
        #expect(RelevanceOrder.building(ofRoom: [nil, "Aula B.3.2"], in: rooms) == "B")
        #expect(RelevanceOrder.building(ofRoom: ["co11", nil], in: rooms) == "N")
        #expect(RelevanceOrder.building(ofRoom: [nil, " "], in: rooms) == nil)
        #expect(RelevanceOrder.building(ofRoom: ["Z.9"], in: rooms) == nil)
    }

    @Test("R13: sono visibili gli edifici il cui segnaposto è nella regione inquadrata")
    func test_R13_visibleBuildings() {
        let pins = [
            MapPin(id: "in", name: "in", coordinate: .init(latitude: 45.478, longitude: 9.227), freeRooms: nil, totalRooms: 1),
            MapPin(id: "out", name: "out", coordinate: .init(latitude: 45.503, longitude: 9.156), freeRooms: nil, totalRooms: 1),
        ]
        let region = MKCoordinateRegion(
            center: .init(latitude: 45.478, longitude: 9.228),
            span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01))
        #expect(MapPlacement.buildings(in: region, among: pins) == ["in"])
    }

    @Test("R9: mentre le aule arrivano le righe mostrate restano ferme e le nuove vanno sotto")
    func test_R9_listStaysStill() {
        let merged = StableOrder.merge(shown: ["m", "z"], sorted: ["a", "m", "q", "z"], settle: false)
        #expect(merged == ["m", "z", "a", "q"])
    }

    @Test("R9: una riga che non c'è più esce, e a caricamento finito la lista prende il suo ordine")
    func test_R9_listSettles() {
        #expect(StableOrder.merge(shown: ["m", "gone", "z"], sorted: ["a", "m", "z"], settle: false) == ["m", "z", "a"])
        #expect(StableOrder.merge(shown: ["m", "z"], sorted: ["a", "m", "z"], settle: true) == ["a", "m", "z"])
        #expect(StableOrder.merge(shown: [String](), sorted: ["b", "a"], settle: false) == ["b", "a"])
    }

    @Test("R24: libera ora cambia mezz'ora prima di una prenotazione e alla sua fine")
    func test_R24_boundaries() {
        let rooms = [schedule("A", [booking("A-0", from: 3600, to: 7200)]),
                     schedule("B", [booking("B-0", from: 5400, to: 9000)])]
        #expect(BoundaryClock.next(after: noon, in: rooms) == noon.addingTimeInterval(1800))
        #expect(BoundaryClock.next(after: noon.addingTimeInterval(1800), in: rooms) == noon.addingTimeInterval(3600))
        #expect(BoundaryClock.next(after: noon.addingTimeInterval(3600), in: rooms) == noon.addingTimeInterval(7200))
        #expect(BoundaryClock.next(after: noon.addingTimeInterval(9000), in: rooms) == nil)
    }

    @Test("R24: senza prenotazioni non c'è niente da aspettare")
    func test_R24_nothingToWaitFor() {
        #expect(BoundaryClock.next(after: noon, in: [schedule("A", [])]) == nil)
        #expect(BoundaryClock.next(after: noon, in: []) == nil)
    }

    @Test("R25: a un confine si richiedono solo le aule che cambiano in quell'istante")
    func test_R25_onlyChangingRooms() {
        let rooms = [schedule("A", [booking("A-0", from: 3600, to: 7200)]),
                     schedule("B", [booking("B-0", from: 5400, to: 7200)]),
                     schedule("C", [booking("C-0", from: -3600, to: 1800)])]
        #expect(BoundaryClock.rooms(changingAt: noon.addingTimeInterval(1800), in: rooms) == ["A", "C"])
        #expect(BoundaryClock.rooms(changingAt: noon.addingTimeInterval(7200), in: rooms) == ["A", "B"])
        #expect(BoundaryClock.rooms(changingAt: noon.addingTimeInterval(600), in: rooms).isEmpty)
    }
}

/// A campus pass listing its rooms as each batch answers.
@Suite("Aule: arrivo a gruppi", .tags(.network, .timing))
@MainActor
struct RoomsArrivalTests {
    /// A day that is not today, so no pass writes the widget's snapshot.
    private let day = PoliMiDate.time(12, on: Date(timeIntervalSince1970: 1_772_000_000))

    private func room(_ id: String, building: String, occupancy: String) -> Classroom {
        Classroom(id: id, capacity: 40, buildingCode: building, floorCode: "0",
                  campusName: "Test arrivo", occupancyID: occupancy)
    }

    @Test("P3: il primo gruppo di aule è in lista mentre il resto della sede è ancora in viaggio")
    func test_P3_firstBatchIsListedBeforeTheRest() async {
        let run = UUID().uuidString
        let slow = "gate-\(run)"
        let arrived = GatedOccupancyStub.hold(slow)
        defer { GatedOccupancyStub.release(slow) }
        // The far room is first in the catalogue and last to be asked about.
        let rooms = [room("FAR", building: "far", occupancy: slow)]
            + (1...8).map { room("N\($0)", building: "near", occupancy: "open-\(run)-\($0)") }
        let model = FreeRoomsModel(catalogue: ArrivalCatalogue(rooms), session: GatedOccupancyStub.session)
        model.day = day
        model.campus = "Test arrivo"
        model.visibleBuildings = ["near"]

        let batches = Counter()
        let pass = Task { await model.load(force: false) { batches.count += 1 } }
        for await _ in arrived { break }

        #expect(Set(model.rooms.map(\.id)) == Set((1...8).map { "N\($0)" }))
        #expect(model.isLoading)
        #expect(model.progress.done == 8 && model.progress.total == 9)
        #expect(batches.count == 1)

        GatedOccupancyStub.release(slow)
        await pass.value
        #expect(model.rooms.count == 9)
        #expect(model.rooms.last?.id == "FAR")
        #expect(batches.count == 2)
        #expect(!model.isLoading)
    }

    @Test("R13: le aule degli edifici inquadrati sono le prime richieste")
    func test_R13_visibleBuildingIsAskedFirst() async {
        let run = UUID().uuidString
        let slow = "gate-\(run)"
        let arrived = GatedOccupancyStub.hold(slow)
        defer { GatedOccupancyStub.release(slow) }
        let rooms = (1...8).map { room("O\($0)", building: "other", occupancy: "other-\(run)-\($0)") }
            + [room("SEEN", building: "seen", occupancy: slow)]
        let model = FreeRoomsModel(catalogue: ArrivalCatalogue(rooms), session: GatedOccupancyStub.session)
        model.day = day
        model.campus = "Test arrivo"
        model.visibleBuildings = ["seen"]

        let pass = Task { await model.load() }
        for await _ in arrived { break }
        // The room in view is in the first batch, so the ninth is not yet asked.
        #expect(GatedOccupancyStub.requests(for: "other-\(run)-8") == 0)

        GatedOccupancyStub.release(slow)
        await pass.value
        #expect(model.rooms.first?.id == "SEEN")
        #expect(model.rooms.count == 9)
    }
}

/// Counts on the main actor.
@MainActor
private final class Counter {
    var count = 0
}

/// A fixed list of rooms.
@MainActor
private final class ArrivalCatalogue: RoomCatalogue {
    let rooms: [Classroom]
    var campuses: [String] { Array(Set(rooms.compactMap(\.campusName))).sorted() }
    init(_ rooms: [Classroom]) { self.rooms = rooms }
    func load(force: Bool) async {}
}
