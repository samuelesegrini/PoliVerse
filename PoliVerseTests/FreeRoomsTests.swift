import Foundation
import Testing
@testable import PoliVerse

/// Free time is derived by subtracting bookings from the teaching day, so the
/// arithmetic is what decides whether a student walks into an occupied room.
/// Errors in the safe direction (a free room shown busy) are tolerable; the
/// opposite is not.
@Suite("Free rooms")
struct FreeRoomsTests {
    private let calendar = PoliMiDate.romeCalendar

    /// A fixed day, so nothing here depends on when the suite runs.
    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        PoliMiDate.time(hour, minute, on: day)
    }

    private var teachingDay: DateInterval {
        DateInterval(start: at(8), end: at(20))
    }

    private func room(_ bookings: [(Int, Int)]) -> RoomSchedule {
        RoomSchedule(
            id: "r", name: "Aula", building: nil, seats: nil,
            bookings: bookings.enumerated().map { index, span in
                RoomBooking(id: "b\(index)", start: at(span.0), end: at(span.1), title: nil)
            })
    }

    private func spans(_ slots: [DateInterval]) -> [String] {
        slots.map(RoomScheduleView.format)
    }

    @Test("A room with nothing booked is free all day")
    func emptyRoom() {
        #expect(spans(room([]).freeSlots(in: teachingDay)) == ["08:00–20:00"])
    }

    @Test("Gaps are the time between bookings")
    func gapsBetweenBookings() {
        let free = room([(9, 11), (14, 16)]).freeSlots(in: teachingDay)
        #expect(spans(free) == ["08:00–09:00", "11:00–14:00", "16:00–20:00"])
    }

    /// The case that makes naive subtraction wrong: a lecture and an exam
    /// booked over the same hour. Subtracting one at a time would report the
    /// second booking's hours as free.
    @Test("Overlapping bookings do not reopen the overlap")
    func overlappingBookings() {
        let free = room([(9, 12), (10, 11)]).freeSlots(in: teachingDay)
        #expect(spans(free) == ["08:00–09:00", "12:00–20:00"])
    }

    @Test("Back-to-back bookings leave no gap between them")
    func adjacentBookings() {
        let free = room([(9, 11), (11, 13)]).freeSlots(in: teachingDay)
        #expect(spans(free) == ["08:00–09:00", "13:00–20:00"])
    }

    @Test("A booking running past the day is clamped to it")
    func bookingOutsideDay() {
        let free = room([(6, 9), (19, 22)]).freeSlots(in: teachingDay)
        #expect(spans(free) == ["09:00–19:00"])
    }

    @Test("A room booked all day has no free slots")
    func fullyBooked() {
        #expect(room([(8, 20)]).freeSlots(in: teachingDay).isEmpty)
    }

    @Test("Slots shorter than the minimum are not offered")
    func minimumLength() {
        let busy = room([(8, 12), (12, 13), (13, 20)])
        #expect(busy.freeSlots(in: teachingDay).isEmpty)

        let shortGap = room([(8, 12), (12, 30), (13, 20)])
        // A twenty-minute gap is not somewhere to go and sit.
        #expect(shortGap.freeSlots(in: teachingDay, minimumMinutes: 30).isEmpty)
    }

    @Test("A two-hour filter keeps only the long gaps")
    func longGapsOnly() {
        let free = room([(9, 10), (11, 12)]).freeSlots(in: teachingDay, minimumMinutes: 120)
        #expect(spans(free) == ["12:00–20:00"])
    }

    @Test("isFree answers for an arbitrary window")
    func isFreeWindow() {
        let busy = room([(9, 11)])
        #expect(!busy.isFree(during: DateInterval(start: at(10), end: at(10, 30))))
        #expect(!busy.isFree(during: DateInterval(start: at(8), end: at(9, 30))))
        #expect(busy.isFree(during: DateInterval(start: at(11), end: at(12))))
    }

    @Test("Merging collapses overlapping and touching intervals")
    func merging() {
        let merged = RoomSchedule.merge([
            DateInterval(start: at(9), end: at(11)),
            DateInterval(start: at(10), end: at(12)),
            DateInterval(start: at(12), end: at(13)),
            DateInterval(start: at(15), end: at(16)),
        ])
        #expect(spans(merged) == ["09:00–13:00", "15:00–16:00"])
    }

    /// A slot missing either end cannot be subtracted, and guessing would mark
    /// a busy room free. It must be dropped, leaving the room looking busier
    /// than it is rather than emptier.
    @Test("A booking with only one timestamp is dropped, not half-read")
    func incompleteBookingDropped() {
        let fields: [String: JSONValue] = ["inizio": .string("2026-03-10T09:00:00")]
        #expect(RoomBooking(fields: fields, roomID: "r", index: 0) == nil)
    }

    @Test("A room row decodes with its bookings")
    func roomDecoding() {
        let json = """
        [{"id_aula": "3.0.1", "nome": "Aula 3.0.1", "capienza": 120,
          "impegni": [{"inizio": "2026-03-10T09:00:00", "fine": "2026-03-10T11:00:00",
                       "descrizione": "Analisi"}]}]
        """
        let rooms = (try? JSONDecoder().decode(AuleResponse.self, from: Data(json.utf8)))?.rooms ?? []
        #expect(rooms.count == 1)
        #expect(rooms[0].seats == 120)
        #expect(rooms[0].bookings.count == 1)
        #expect(rooms[0].bookings.first?.title == "Analisi")
    }

    /// A room with no bookings is the most interesting row on the screen, so
    /// an absent list must not disqualify it.
    @Test("A room with no bookings still decodes")
    func roomWithoutBookings() {
        let json = """
        [{"id_aula": "B.2.2", "nome": "Aula B.2.2"}]
        """
        let rooms = (try? JSONDecoder().decode(AuleResponse.self, from: Data(json.utf8)))?.rooms ?? []
        #expect(rooms.count == 1)
        #expect(rooms[0].bookings.isEmpty)
    }

    @Test("Sites decode from either naming")
    func siteDecoding() {
        let json = """
        {"sedi": [{"id_sede": "MIA", "descrizione": "Milano Leonardo"}]}
        """
        let sites = (try? JSONDecoder().decode(SediResponse.self, from: Data(json.utf8)))?.sites ?? []
        #expect(sites.count == 1)
        #expect(sites[0].name == "Milano Leonardo")
    }
}
