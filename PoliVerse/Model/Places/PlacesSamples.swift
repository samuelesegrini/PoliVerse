import CoreLocation
import Foundation

// Sample data for this area: what its screens show when the student chose
// "Esplora con dati di esempio", and what the previews render.
//
// Real names from an Ingegneria Informatica plan, so layout is tested against
// realistic string lengths rather than "Lorem ipsum". This ships — an
// incoherent demo is something a student sees.

/// The sample campuses.
nonisolated extension AuleSite {
    /// Milano Leonardo and Milano Bovisa.
    ///
    /// - Returns: The sample campuses.
    static func samples() -> [AuleSite] {
        [
            AuleSite(id: "MIA", name: "Milano Leonardo"),
            AuleSite(id: "MIB", name: "Milano Bovisa"),
        ]
    }
}

/// The sample room bookings.
nonisolated extension RoomSchedule {
    /// The rooms the sample week's lessons are in, booked with those same
    /// lessons — so a room opened from Oggi shows the lesson that sent the
    /// student there, plus what comes after it.
    static func samples(on day: Date) -> [RoomSchedule] {
        let calendar = PoliMiDate.romeCalendar
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func named(_ code: String) -> String { SampleDegree.teaching(code).name }
        var id = 0
        func booking(_ from: (Int, Int), _ to: (Int, Int), _ title: String) -> RoomBooking {
            id += 1
            return RoomBooking(id: "b\(id)", start: at(from.0, from.1), end: at(to.0, to.1), title: title)
        }

        return [
            RoomSchedule(id: "R.0.1", name: "Aula Rogers", building: "Edificio 3",
                         seats: 320, bookings: [
                             booking((8, 15), (10, 0), named("095948")),
                             booking((10, 15), (13, 0), named("086657")),
                             booking((14, 30), (16, 30), "Seminario — sistemi distribuiti"),
                         ]),
            RoomSchedule(id: "D.0.2", name: "Aula De Donato", building: "Edificio 3",
                         seats: 240, bookings: [
                             booking((10, 15), (13, 0), named("086657")),
                             booking((14, 30), (17, 0), named("089156")),
                         ]),
            RoomSchedule(id: "C.1.1", name: "Aula Castigliano", building: "Edificio 5",
                         seats: 180, bookings: [
                             booking((9, 15), (12, 0), named("095857")),
                         ]),
            RoomSchedule(id: "L.0.5", name: "Lab Informatico", building: "Edificio 21",
                         seats: 60, bookings: [
                             booking((14, 15), (16, 0), named("095948") + " — esercitazione"),
                         ]),
            RoomSchedule(id: "L.1.2", name: "Lab Reti", building: "Edificio 21",
                         seats: 48, bookings: [
                             booking((9, 15), (12, 0), named("086657") + " — laboratorio"),
                         ]),
            RoomSchedule(id: "B.1.4", name: "Aula Beta", building: "Edificio 24",
                         seats: 90, bookings: [
                             booking((14, 15), (17, 0), named("095857")),
                         ]),
            // Free all day: the app has to be able to say so.
            RoomSchedule(id: "A.2.3", name: "Aula Alfa", building: "Edificio 24",
                         seats: 120, bookings: []),
        ]
    }
}

/// The sample room catalogue.
nonisolated extension Classroom {
    /// Three real Città Studi and Bovisa rooms, with the building, floor, capacity and
    /// the three identifiers the real catalogue carries.
    ///
    /// - Returns: The sample rooms.
    static func samples() -> [Classroom] {
        [
            Classroom(id: "3.0.1", capacity: 120, buildingCode: "MIA0103",
                      floorCode: "MIA0103000", buildingName: "Edificio 3",
                      floorName: "Piano terra", campusName: "Milano Leonardo",
                      address: "Piazza Leonardo da Vinci 32, Milano",
                      accessibleSeats: 4, occupancyID: "32",
                      roomCode: "MIA0103000001"),
            Classroom(id: "2.1.4", capacity: 80, buildingCode: "MIA0102",
                      floorCode: "MIA0102001", buildingName: "Edificio 2",
                      floorName: "Primo piano", campusName: "Milano Leonardo",
                      address: "Piazza Leonardo da Vinci 32, Milano",
                      occupancyID: "67", roomCode: "MIA0102001004"),
            Classroom(id: "B.2.2", capacity: 60, buildingCode: "MIB0202",
                      floorCode: "MIB0202002", buildingName: "Edificio B2",
                      floorName: "Secondo piano", campusName: "Milano Bovisa",
                      address: "Via Candiani 72, Milano",
                      occupancyID: "1541", roomCode: "MIB0202002002"),
        ]
    }
}

/// The sample room equipment.
nonisolated extension RoomFacility {
    /// A projector, a radio microphone and seats with power — the items the real
    /// catalogue lists most often.
    ///
    /// - Returns: The sample equipment.
    static func samples() -> [RoomFacility] {
        [
            RoomFacility(id: 4, it: "Video proiettore", en: "Video projector"),
            RoomFacility(id: 5, it: "Radio microfono", en: "Radio microphone"),
            RoomFacility(id: 142, it: "Postazioni dotate di presa elettrica",
                         en: "Seats with electric socket"),
        ]
    }
}

/// The sample map pins.
nonisolated extension MapPin {
    /// Three buildings at their real coordinates, one of each availability: mostly free,
    /// mostly busy, and not yet counted.
    ///
    /// - Returns: The sample pins.
    static func samples() -> [MapPin] {
        [
            MapPin(id: "MIA0103", name: "Edificio 3",
                   coordinate: .init(latitude: 45.4788, longitude: 9.2272),
                   freeRooms: 7, totalRooms: 9),
            MapPin(id: "MIA0102", name: "Edificio 2",
                   coordinate: .init(latitude: 45.4781, longitude: 9.2288),
                   freeRooms: 2, totalRooms: 11),
            MapPin(id: "MIB0202", name: "Edificio B2",
                   coordinate: .init(latitude: 45.5030, longitude: 9.1560),
                   freeRooms: nil, totalRooms: 21),
        ]
    }
}
