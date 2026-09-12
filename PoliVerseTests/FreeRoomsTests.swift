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

/// A 401 from the Politecnico means several different things, and the app
/// reacted to all of them by offering a login. `ws_aule` exposed it: a service
/// refused to student accounts by design put a re-authentication banner across
/// an app in which everything else was working.
@Suite("Refusal classification")
struct RefusalTests {
    private let notEnabled = """
    {"statusCode":401,"message":"jaf.model2.exceptions.JafUnauthorizedException: \
    Utente non abilitato Code: 6"}
    """
    private let badScope = """
    {"statusCode":401,"message":"jaf.model2.exceptions.JafUnauthorizedException: \
    Scope OAuth non valido. Effettuare logout/login o disinstallare e \
    reinstallare l'applicazione. Code: 33"}
    """

    @Test("\"Utente non abilitato\" is not read as a dead session")
    func notEnabledIsNotScope() {
        #expect(PoliMiAPI.isNotEntitled(notEnabled))
        #expect(!PoliMiAPI.isInvalidScope(notEnabled))
    }

    @Test("A genuine scope failure is still recognised")
    func realScopeFailure() {
        #expect(PoliMiAPI.isInvalidScope(badScope))
        #expect(!PoliMiAPI.isNotEntitled(badScope))
    }

    /// The guard that keeps one optional service from speaking for the whole
    /// session.
    @Test("Only services the app depends on can invalidate the session")
    func onlyEssentialServicesBreakTheSession() {
        #expect(!APIHost.wsAule.refusalMeansBrokenSession)
        for host in [APIHost.app, .iae, .agenda, .libretto, .weBeep] {
            #expect(host.refusalMeansBrokenSession)
        }
    }

    @Test("A refusal is permanent, so it is never retried")
    func refusalIsPermanent() {
        #expect(APIError.notEntitled("/cata/sedi", body: "").isPermanent)
    }
}

/// `/ricerca/aula/occupazione/{idaula}/{yyyy-MM-dd}` — the public endpoint the
/// WADL gave up, after `ws_aule` turned out to be staff-only.
@Suite("Occupancy bands")
struct OccupancyBandTests {
    private var day: Date {
        PoliMiDate.romeCalendar.date(
            from: DateComponents(year: 2026, month: 9, day: 11, hour: 12))!
    }

    private func bands(_ json: String) -> [RoomBooking] {
        let decoded = (try? JSONDecoder().decode([OccupancyBand].self, from: Data(json.utf8))) ?? []
        return decoded.enumerated().compactMap { index, band in
            band.toBooking(roomID: "2.0.1", on: day, index: index)
        }
    }

    /// The exact body a real room returned on a teaching day.
    @Test("The real payload becomes bookings on the requested day")
    func realPayload() {
        let parsed = bands("""
        [{"inizio":"08:15","fine":"10:15"},{"inizio":"10:15","fine":"12:15"},
         {"inizio":"13:15","fine":"15:15"},{"inizio":"15:15","fine":"17:15"},
         {"inizio":"17:15","fine":"19:15"}]
        """)
        #expect(parsed.count == 5)
        #expect(RoomScheduleView.format(parsed[0].interval) == "08:15–10:15")
        #expect(RoomScheduleView.format(parsed[4].interval) == "17:15–19:15")
    }

    /// A closed day: the service returns an empty array, and the room is free
    /// all day rather than missing.
    @Test("An empty day leaves the room free")
    func closedDay() {
        let room = RoomSchedule(id: "2.0.1", name: "2.0.1", building: nil,
                                seats: nil, bookings: bands("[]"))
        let window = DateInterval(start: PoliMiDate.time(8, on: day),
                                  end: PoliMiDate.time(20, on: day))
        #expect(room.freeSlots(in: window).count == 1)
    }

    @Test("The free gaps between real bands are found")
    func gapsFromRealBands() {
        let room = RoomSchedule(
            id: "2.0.1", name: "2.0.1", building: nil, seats: nil,
            bookings: bands("""
            [{"inizio":"08:15","fine":"10:15"},{"inizio":"13:15","fine":"15:15"}]
            """))
        let window = DateInterval(start: PoliMiDate.time(8, on: day),
                                  end: PoliMiDate.time(20, on: day))
        #expect(room.freeSlots(in: window).map(RoomScheduleView.format)
            == ["10:15–13:15", "15:15–20:00"])
    }

    @Test("A band missing either time is dropped rather than half-read")
    func incompleteBand() {
        let json = """
        [{"inizio":"08:15"}]
        """
        #expect(bands(json).isEmpty)
    }
}

/// The refusal codes are matched on text, so the matching has to be exact
/// enough not to swallow neighbouring codes.
@Suite("Refusal code matching")
struct RefusalCodeTests {
    private func body(_ code: Int, _ message: String) -> String {
        """
        {"statusCode":401,"message":"jaf.model2.exceptions.JafUnauthorizedException: \
        \(message) Code: \(code)"}
        """
    }

    @Test("Code 6 is a permissions refusal")
    func codeSix() {
        #expect(PoliMiAPI.isNotEntitled(body(6, "Utente non abilitato")))
    }

    /// The bug this pins: `contains("Code: 6")` also matches 60 and 66, which
    /// would report a broken session as a permissions problem and never offer
    /// the login that fixes it.
    @Test("Codes starting with 6 are not mistaken for code 6")
    func neighbouringCodes() {
        for code in [60, 61, 66, 666] {
            #expect(!PoliMiAPI.isNotEntitled(body(code, "Qualcos'altro")),
                    "Code \(code) must not read as code 6")
        }
    }

    @Test("Code 33 stays a scope failure, and still invalidates the session")
    func codeThirtyThree() {
        let scope = body(33, "Scope OAuth non valido.")
        #expect(!PoliMiAPI.isNotEntitled(scope))
        #expect(PoliMiAPI.isInvalidScope(scope))
    }
}

/// Which services may report a refusal as a fact about the account, and which
/// must treat the same body as a broken session.
///
/// The distinction is not cosmetic: `iae` and `libretto` recover from a 401 by
/// dropping the token and re-authenticating. Reading their refusal as a
/// permissions problem removed that recovery — career went permanently blank
/// with "your profile lacks access" while everything else worked.
@Suite("Refusal routing")
struct RefusalRoutingTests {
    private let refusal = """
    {"statusCode":401,"message":"jaf.model2.exceptions.JafUnauthorizedException: \
    Utente non abilitato Code: 6"}
    """

    @Test("The body reads as a refusal whatever the host")
    func bodyClassification() {
        #expect(PoliMiAPI.isNotEntitled(refusal))
    }

    /// The routing that matters: only an optional service may keep it.
    @Test("Essential services treat a refusal as a session to repair")
    func essentialHostsRecover() {
        for host in [APIHost.app, .iae, .agenda, .libretto, .weBeep] {
            #expect(host.refusalMeansBrokenSession,
                    "\(host) must be able to re-authenticate on a 401")
        }
        #expect(!APIHost.wsAule.refusalMeansBrokenSession)
    }
}
