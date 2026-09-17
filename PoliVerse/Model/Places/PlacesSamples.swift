import CoreLocation
import Foundation

/// Sample data for this area: what its screens show when the student chose
/// "Esplora con dati di esempio", and what the previews render.
///
/// Real names from an Ingegneria Informatica plan, so layout is tested against
/// realistic string lengths rather than "Lorem ipsum". This ships — an
/// incoherent demo is something a student sees.

nonisolated extension AuleSite {
    static func samples() -> [AuleSite] {
        [
            AuleSite(id: "MIA", name: "Milano Leonardo"),
            AuleSite(id: "MIB", name: "Milano Bovisa"),
        ]
    }
}

nonisolated extension RoomSchedule {
    static func samples(on day: Date) -> [RoomSchedule] {
        let calendar = PoliMiDate.romeCalendar
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        return [
            RoomSchedule(id: "3.0.1", name: "Aula 3.0.1", building: "Edificio 3",
                         seats: 120, bookings: [
                             RoomBooking(id: "a", start: at(8, 15), end: at(10, 15),
                                         title: "Analisi Matematica 2"),
                             RoomBooking(id: "b", start: at(14), end: at(16),
                                         title: "Fisica Tecnica"),
                         ]),
            RoomSchedule(id: "2.1.4", name: "Aula 2.1.4", building: "Edificio 2",
                         seats: 80, bookings: [
                             RoomBooking(id: "c", start: at(10, 15), end: at(13, 15),
                                         title: "Reti Logiche"),
                         ]),
            RoomSchedule(id: "B.2.2", name: "Aula B.2.2", building: "Edificio B",
                         seats: 60, bookings: []),
        ]
    }
}

nonisolated extension Classroom {
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

nonisolated extension RoomFacility {
    static func samples() -> [RoomFacility] {
        [
            RoomFacility(id: 4, it: "Video proiettore", en: "Video projector"),
            RoomFacility(id: 5, it: "Radio microfono", en: "Radio microphone"),
            RoomFacility(id: 142, it: "Postazioni dotate di presa elettrica",
                         en: "Seats with electric socket"),
        ]
    }
}

nonisolated extension MapPin {
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
