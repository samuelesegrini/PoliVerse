import Foundation
import Testing
@testable import PoliVerse

/// The campus catalogue, which arrives as four separate lists and is only
/// useful once they are joined.
///
/// Untestable until the catalogue moved onto ``HTTP``: the model built its own
/// `URLSession` against a hardcoded host, so the join — four dictionaries, a
/// sort, and the rule about which rooms are real — could only be exercised by
/// actually calling the Politecnico.
@Suite("Room catalogue")
@MainActor
struct RoomCatalogueTests {
    /// The five endpoints, keyed exactly as ``RoomsModel`` asks for them.
    private static func catalogue(
        rooms: String = "[]", buildings: String = "[]",
        campuses: String = "[]", floors: String = "[]", sites: String = "[]"
    ) -> FixtureHTTP {
        FixtureHTTP([
            "/spazi/aula": Data(rooms.utf8),
            "/spazi/edificio": Data(buildings.utf8),
            "/spazi/campus": Data(campuses.utf8),
            "/spazi/piano": Data(floors.utf8),
            "/spazi/sede": Data(sites.utf8),
        ])
    }

    /// A cache file of its own, so a test can never overwrite the catalogue the
    /// developer's app is holding.
    private func model(_ http: FixtureHTTP) -> RoomsModel {
        RoomsModel(http: http, cacheName: "rooms-test-\(UUID().uuidString)")
    }

    /// The whole point of the four-way join: a room arrives knowing only two
    /// opaque codes, and the names come from the other three lists.
    @Test("A room is joined to its building, campus and floor")
    func joinsTheFourLists() async throws {
        let http = Self.catalogue(
            rooms: #"[{"sigla": "3.0.1", "csie": "E1", "csip": "P0", "capienza": "120"}]"#,
            buildings: #"[{"csie": "E1", "csic": "C1", "nome": "Edificio 3"}]"#,
            campuses: #"[{"csic": "C1", "nome": "Leonardo"}]"#,
            floors: #"[{"csip": "P0", "csie": "E1", "nome": "Piano terra"}]"#)
        let rooms = model(http)

        await rooms.load()

        let room = try #require(rooms.rooms.first)
        #expect(room.id == "3.0.1")
        #expect(room.capacity == 120)
        #expect(room.buildingName == "Edificio 3")
        #expect(room.campusName == "Leonardo")
        #expect(room.floorName == "Piano terra")
    }

    /// The service names campuses by address; the site is what a student calls
    /// the place, and what the favourite is chosen among.
    @Test("A room knows its site, and a site opens on its biggest campus")
    func joinsTheSite() async throws {
        let http = Self.catalogue(
            rooms: #"[{"sigla": "B1", "csie": "E1", "csip": "P0", "capienza": "80"}, {"sigla": "B2", "csie": "E1", "csip": "P0", "capienza": "80"}, {"sigla": "D1", "csie": "E2", "csip": "P0", "capienza": "40"}]"#,
            buildings: #"[{"csie": "E1", "csic": "MIB01", "nome": "B"}, {"csie": "E2", "csic": "MIB02", "nome": "D"}]"#,
            campuses: #"[{"csic": "MIB01", "csis": "MIB", "nome": "Via La Masa"}, {"csic": "MIB02", "csis": "MIB", "nome": "Via Durando"}]"#,
            sites: #"[{"csis": "MIB", "nome": "Milano Bovisa"}]"#)
        let rooms = model(http)

        await rooms.load()

        #expect(rooms.rooms.first?.siteName == "Milano Bovisa")
        #expect(rooms.sites == ["Milano Bovisa"])
        #expect(rooms.biggestSite == "Milano Bovisa")
        #expect(rooms.mainCampus(inSite: "Milano Bovisa") == "Via La Masa")
    }

    /// Rooms the catalogue marks as fictitious or out of service are still in
    /// the payload. A room with no code, or no seats, is not somewhere anyone
    /// can be sent.
    @Test("Rooms with no code or no seats are not in the catalogue")
    func dropsUnusableRooms() async {
        let http = Self.catalogue(rooms: """
        [{"sigla": "3.0.1", "csie": "E1", "csip": "P0", "capienza": "120"},
         {"sigla": "", "csie": "E1", "csip": "P0", "capienza": "50"},
         {"sigla": "FITTIZIA", "csie": "E1", "csip": "P0", "capienza": "0"},
         {"sigla": "NOFLOOR", "csie": "E1", "capienza": "30"}]
        """)
        let rooms = model(http)

        await rooms.load()

        #expect(rooms.rooms.map(\.id) == ["3.0.1"])
    }

    /// Read from view bodies — the map's campus picker among them — so it is
    /// derived once on write rather than by a `Set` over 350 rooms per render.
    @Test("Campuses are derived from the rooms, sorted and unique")
    func campusesAreDerived() async {
        let http = Self.catalogue(
            rooms: """
            [{"sigla": "A", "csie": "E1", "csip": "P0", "capienza": "10"},
             {"sigla": "B", "csie": "E2", "csip": "P0", "capienza": "10"},
             {"sigla": "C", "csie": "E1", "csip": "P0", "capienza": "10"}]
            """,
            buildings: """
            [{"csie": "E1", "csic": "C2", "nome": "Uno"},
             {"csie": "E2", "csic": "C1", "nome": "Due"}]
            """,
            campuses: #"[{"csic": "C1", "nome": "Bovisa"}, {"csic": "C2", "nome": "Leonardo"}]"#)
        let rooms = model(http)

        await rooms.load()

        #expect(rooms.campuses == ["Bovisa", "Leonardo"])
    }

    /// A room whose building is missing from the other list is still a room —
    /// it just has no name to show beside it. Dropping it would take a real
    /// place off the map because a lookup table was incomplete.
    @Test("A room survives a building the catalogue does not describe")
    func unknownBuildingIsNotFatal() async throws {
        let http = Self.catalogue(
            rooms: #"[{"sigla": "3.0.1", "csie": "E9", "csip": "P0", "capienza": "120"}]"#,
            buildings: #"[{"csie": "E1", "csic": "C1", "nome": "Edificio 3"}]"#)
        let rooms = model(http)

        await rooms.load()

        let room = try #require(rooms.rooms.first)
        #expect(room.buildingName == nil)
        #expect(room.campusName == nil)
    }

    /// The catalogue changes rarely, so a second visit must not refetch.
    @Test("A loaded catalogue is not fetched again without being forced")
    func doesNotRefetch() async {
        let http = Self.catalogue(
            rooms: #"[{"sigla": "3.0.1", "csie": "E1", "csip": "P0", "capienza": "120"}]"#)
        let rooms = model(http)

        await rooms.load()
        await rooms.load()

        // Five paths, once each.
        #expect(await http.requests.count == 5)
    }

    @Test("A failure is reported and leaves the catalogue empty rather than wrong")
    func failureIsReported() async {
        let rooms = model(FixtureHTTP.failing(APIError.badStatus(503, body: "down")))

        await rooms.load()

        #expect(rooms.rooms.isEmpty)
        #expect(rooms.errorMessage != nil)
    }

    @Test("Search matches a room by its code, building or campus")
    func searchAcrossFields() async {
        let http = Self.catalogue(
            rooms: #"[{"sigla": "3.0.1", "csie": "E1", "csip": "P0", "capienza": "120"}]"#,
            buildings: #"[{"csie": "E1", "csic": "C1", "nome": "Trifoglio"}]"#,
            campuses: #"[{"csic": "C1", "nome": "Leonardo"}]"#)
        let rooms = model(http)
        await rooms.load()

        #expect(rooms.rooms(matching: "3.0", campus: nil).count == 1)
        #expect(rooms.rooms(matching: "trifoglio", campus: nil).count == 1)
        #expect(rooms.rooms(matching: "leonardo", campus: nil).count == 1)
        #expect(rooms.rooms(matching: "bovisa", campus: nil).isEmpty)
        // A campus filter excludes before the query is even considered.
        #expect(rooms.rooms(matching: "", campus: "Bovisa").isEmpty)
    }
}
