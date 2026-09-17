import Foundation
import Testing
@testable import PoliVerse

/// Which lesson the tab bar accessory shows.
@Suite("Current class")
struct CurrentClassTests {
    private let calendar = PoliMiDate.romeCalendar
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 11))! }

    private func event(_ id: Int, _ from: Double, _ to: Double, _ kind: EventKind = .lecture) -> AgendaEvent {
        AgendaEvent(id: id, title: "L\(id)", start: now.addingTimeInterval(from * 3600),
                    end: now.addingTimeInterval(to * 3600), kind: kind, room: nil, roomAcronym: nil, calendarName: nil)
    }

    @Test("A lesson in progress wins over the next one")
    func ongoing() throws {
        let current = try #require(CurrentClass.pick(from: [event(2, 2, 3), event(1, -0.5, 0.5)], now: now, calendar: calendar))
        #expect(current.event.id == 1)
        #expect(current.isOngoing)
        #expect(abs(current.progress(at: now) - 0.5) < 0.001)
    }

    @Test("Otherwise the next lesson today; ended lessons, deadlines and tomorrow are skipped")
    func next() throws {
        let events = [event(1, -3, -2), event(2, 1, 1, .deadline), event(3, 2, 3), event(4, 24, 25)]
        let current = try #require(CurrentClass.pick(from: events, now: now, calendar: calendar))
        #expect(current.event.id == 3)
        #expect(!current.isOngoing)
        #expect(CurrentClass.pick(from: [event(1, -3, -2)], now: now, calendar: calendar) == nil)
    }

    @Test("The accessory wakes at the next start or end of a lesson today, at most an hour away")
    func nextChange() {
        // An ongoing lesson ends in 30 minutes, before the next one starts.
        let events = [event(1, -0.5, 0.5), event(2, 2, 3), event(3, 1, 1.2, .deadline)]
        #expect(CurrentClass.nextChange(in: events, after: now, calendar: calendar) == now.addingTimeInterval(1800))
        // Nothing within the hour: the hour cap.
        #expect(CurrentClass.nextChange(in: [event(2, 2, 3)], after: now, calendar: calendar) == now.addingTimeInterval(3600))
        // Nothing left today and it is late: tomorrow's start, sooner than the cap.
        let late = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 23, minute: 30))!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16))!
        #expect(CurrentClass.nextChange(in: events, after: late, calendar: calendar) == midnight)
    }
}
