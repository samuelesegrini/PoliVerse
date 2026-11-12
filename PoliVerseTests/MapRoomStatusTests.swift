import Foundation
import Testing
@testable import PoliVerse

@Suite("Stato delle aule nella nuova mappa")
struct MapRoomStatusTests {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { day.addingTimeInterval(minutes * 60) }
    private func booking(_ from: Double, _ to: Double, _ title: String? = nil) -> RoomBooking {
        RoomBooking(id: "a-\(from)", start: at(from), end: at(to), title: title)
    }

    @Test("Senza prenotazioni lette lo stato è sconosciuto, mai libero")
    func unknown() {
        #expect(MapRoomStatus.of(nil, at: at(0), dayEnd: at(600)) == .unknown)
        #expect(!MapRoomStatus.unknown.isFree)
    }

    @Test("Libera fino alla prossima prenotazione")
    func freeUntilNext() {
        let status = MapRoomStatus.of([booking(120, 240)], at: at(0), dayEnd: at(600))
        #expect(status == .free(until: at(120)))
        #expect(status.isFree)
    }

    @Test("Libera per il resto della giornata quando non c'è altro")
    func freeAllDay() {
        #expect(MapRoomStatus.of([booking(0, 60)], at: at(90), dayEnd: at(600)) == .free(until: nil))
        #expect(MapRoomStatus.of([booking(700, 760)], at: at(90), dayEnd: at(600)) == .free(until: nil))
    }

    @Test("Occupata fino alla fine delle lezioni attaccate")
    func busyJoined() {
        let bookings = [booking(0, 105, "Fisica I"), booking(115, 210), booking(300, 360)]
        #expect(MapRoomStatus.of(bookings, at: at(30), dayEnd: at(600)) == .busy(until: at(210), what: "Fisica I"))
    }
}
