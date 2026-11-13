import Foundation
import Testing
@testable import PoliVerse

@Suite("Servizi della nuova mappa")
struct CampusServicesTests {
    // MARK: Opening hours

    @Test func readsTheBarsHoursAsTheServiceWritesThem() {
        #expect(OpeningHours.parse("lun-ven 8:00 – 19:00") == OpeningSpan(weekdays: Set(2...6), opens: 480, closes: 1140))
        #expect(OpeningHours.parse("lun – ven 11:30 – 14:30") == OpeningSpan(weekdays: Set(2...6), opens: 690, closes: 870))
        #expect(OpeningHours.parse("lun-ven 8.00-18.30") == OpeningSpan(weekdays: Set(2...6), opens: 480, closes: 1110))
        // Without days, the working week.
        #expect(OpeningHours.parse("8:00 – 15:00")?.weekdays == Set(2...6))
        #expect(OpeningHours.parse("Da lunedì a sabato: 7.30 - 20.30")?.weekdays == Set(2...7))
        #expect(OpeningHours.parse("Lunedì-sabato dalle 7.30 alle 20.30 (esclusi festivi)")?.closes == 1230)
        #expect(OpeningHours.parse("su prenotazione") == nil)
    }

    @Test func readsTheCarParksWeek() {
        let spans = OpeningHours.parse(week: [
            "lunedi": [["inizio": "07:00", "fine": "20:30"]],
            "sabato": [],
            "domenica": [["inizio": "x", "fine": "y"]],
        ])
        #expect(spans == [OpeningSpan(weekdays: [2], opens: 420, closes: 1230)])
    }

    @Test func saysWhetherItIsOpen() {
        let bar = [OpeningSpan(weekdays: Set(2...6), opens: 480, closes: 1050),
                   OpeningSpan(weekdays: Set(2...6), opens: 690, closes: 870)]
        // Tuesday 12:00: both open, the later closing wins.
        #expect(OpeningHours.state(bar, weekday: 3, minute: 720) == .open(closes: 1050))
        #expect(OpeningHours.state(bar, weekday: 3, minute: 400) == .opensLater(at: 480))
        #expect(OpeningHours.state(bar, weekday: 3, minute: 1050) == .closed)
        // Sunday.
        #expect(OpeningHours.state(bar, weekday: 1, minute: 720) == .closed)
        #expect(OpeningHours.clock(1050) == "17:30")
    }

    // MARK: Points of interest

    private let points = Data("""
    [
     {"id": 7, "location": {"csi": "MIA020500S", "lat": 45.47, "lng": 9.23},
      "tags": {"8": "24317_LBL_TAG_RISTORO", "1": "24317_LBL_TAG_SERVIZI"},
      "props": {"name": "Rist. 3", "denominazione": {"it": "Polidistrict Café Bonardi", "en": "Polidistrict Café Bonardi"},
                "ubicazione": {"it": "Campus Leonardo - Edificio 14 (Nave)", "en": "Leonardo Campus - Building 14"},
                "orario": {"it": {"Bar Caffetteria": "lun-ven 8:00 – 18:30"}, "en": {"Coffee Bar": "Mon–Fri 8:00 AM – 6:30 PM"}}}},
     {"id": 9, "location": {"csi": "MIA04", "lat": 45.478, "lng": 9.235},
      "tags": {"4": "24317_LBL_TAG_PARCHEGGIO"},
      "props": {"name": "Parcheggio Clericetti", "capienza_totale": 121,
                "posti_liberi": {"standard": 100.0, "elettrici": 2.0},
                "orari_apertura": {"lunedi": [{"inizio": "07:00", "fine": "20:30"}]}}},
     {"id": 11, "location": {"csi": "MIA0203001", "lat": 45.47, "lng": 9.22},
      "tags": {"5": "24317_LBL_TAG_BEVERINO"},
      "props": {"name": "Beverino 3", "denominazione": {"it": "Edificio 3, terra", "en": "Building 3, ground"}}},
     {"id": 12, "location": {"csi": "MIB0201000", "lat": 45.5, "lng": 9.15},
      "tags": {"18": "24317_LBL_TAG_STALLO_BICI"},
      "props": {"denominazione": {"it": "Rastrelliera Bovisa"}, "numero_posti": {"in_rastrelliera": 12, "in_archetto": 4}}},
     {"id": 13, "location": {"csi": "MIA0101000"}, "tags": {"7": "24317_LBL_TAG_PLAYGROUND"}, "props": {"name": "Ping pong"}}
    ]
    """.utf8)

    @Test func keepsOnlyTheServicesShown() throws {
        let places = try CampusPlaces.parse(points)
        #expect(places.map(\.service) == [.bar, .parking, .water, .bikes])
    }

    @Test func readsWhereEachPlaceIs() throws {
        let places = try CampusPlaces.parse(points)
        let bar = try #require(places.first { $0.service == .bar })
        #expect(bar.name == "Polidistrict Café Bonardi")
        #expect(bar.detail == "Campus Leonardo - Edificio 14 (Nave)")
        #expect(bar.csie == "MIA0205")
        #expect(bar.csip == "MIA020500S")
        #expect(bar.hours.first?.closes == 1110)
        let water = try #require(places.first { $0.service == .water })
        #expect(water.name == nil)
        #expect(water.detail == "Edificio 3, terra")
        #expect(water.area == "MIA")
    }

    @Test func readsTheCarParksFreeSpacesAndTheRacks() throws {
        let places = try CampusPlaces.parse(points)
        let parking = try #require(places.first { $0.service == .parking })
        #expect(parking.spaces == 100)
        #expect(parking.capacity == 121)
        #expect(parking.csie == nil)
        #expect(parking.area == "MIA")
        #expect(parking.hours.count == 1)
        let bikes = try #require(places.first { $0.service == .bikes })
        #expect(bikes.spaces == 16)
        #expect(bikes.area == "MIB")
    }

    @Test func readsInEnglishWhereTheServiceHasIt() throws {
        let places = try CampusPlaces.parse(points, language: "en")
        #expect(places.first { $0.service == .water }?.detail == "Building 3, ground")
        // Only Italian: kept.
        #expect(places.first { $0.service == .bikes }?.name == "Rastrelliera Bovisa")
    }

    // MARK: Floors

    @Test func readsAFloorsUses() throws {
        let body = Data("""
        {"result": [
          {"tema_id": 1003, "nomeTematismo": "Aule", "voci": [{"description": "T.2.1"}]},
          {"tema_id": 1030, "nomeTematismo": "Destinazioni uso",
           "voci": [{"id_voce": -1}, {"description": "AULA"}, {"description": "WC DISABILE PUBBLICO"},
                    {"description": "SPAZIO STUDIO"}]}
        ]}
        """.utf8)
        #expect(try FloorUses.parse(body) == ["AULA", "WC DISABILE PUBBLICO", "SPAZIO STUDIO"])
        #expect(try FloorUses.parse(Data("{}".utf8)).isEmpty)
    }

    @Test func turnsAFloorsUsesIntoPlaces() {
        let both = CampusPlaces.onFloor(["WC PUBBLICO", "WC DISABILE PUBBLICO", "BIBLIOTECA E SPAZIO CONSULTAZIONE"],
                                        csip: "MIA0203001")
        #expect(both.map(\.service) == [.toilets, .study])
        #expect(both[0].special)
        #expect(both[0].csie == "MIA0203")
        #expect(both[1].special)
        // Staff toilets are not public ones.
        #expect(CampusPlaces.onFloor(["WC", "UFFICIO"], csip: "MIA0203001").isEmpty)
        let study = CampusPlaces.onFloor(["WC PUBBLICO", "SPAZIO STUDIO"], csip: "MIA0101000")
        #expect(!study[0].special)
        #expect(study[1].special == false)
    }

    @Test func putsTheOriginsBuildingFirstThenTheNearest() {
        func place(_ id: String, _ csie: String?) -> CampusPlace {
            CampusPlace(id: id, service: .water, name: nil, detail: nil, csie: csie, csip: nil,
                        latitude: nil, longitude: nil)
        }
        let places = [place("far", "MIA0101"), place("unknown", nil), place("near", "MIA0102"), place("here", "MIA0203")]
        let sorted = CampusPlaces.nearest(places, origin: "MIA0203", metres: ["far": 300, "near": 80, "here": 400])
        #expect(sorted.map(\.id) == ["here", "near", "far", "unknown"])
    }

    // MARK: Access

    @Test func keepsTheBuildingsWithAccessNotes() throws {
        let json = Data("""
        [{"csie": "MIA0203", "noteAccesso": "  Ingresso  con\\nrampa. ", "noteAccessoDisabili": null},
         {"csie": "MIA0101", "noteAccesso": "", "noteAccessoDisabili": null},
         {"csie": "MIA0102"}]
        """.utf8)
        let notes = BuildingAccess.parse(try JSONDecoder().decode([BuildingDTO].self, from: json))
        #expect(notes == ["MIA0203": BuildingAccess(general: "Ingresso con rampa.", accessible: nil)])
    }
}
