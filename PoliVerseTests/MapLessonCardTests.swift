import Foundation
import Testing
@testable import PoliVerse

@Suite("Card della lezione nella nuova mappa")
struct MapLessonCardTests {
    private let calendar = PoliMiDate.romeCalendar
    private var nine: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 9))! }

    private func lesson(_ id: Int, _ from: Double, _ to: Double, kind: EventKind = .lecture) -> AgendaEvent {
        AgendaEvent(id: id, title: "L\(id)", start: nine.addingTimeInterval(from * 3600),
                    end: nine.addingTimeInterval(to * 3600), kind: kind, room: nil, roomAcronym: nil, calendarName: nil)
    }

    @Test func picksTheLessonInProgressAndTheOneAfter() {
        let events = [lesson(3, 5, 7), lesson(1, 0, 2), lesson(2, 2.5, 4)]
        let now = nine.addingTimeInterval(3600)
        #expect(MapLessonCard.pick(events, now: now, calendar: calendar) == .init(current: events[1], next: events[2]))
    }

    @Test func withoutALessonInProgressTheNextOne() {
        let events = [lesson(1, 0, 2), lesson(2, 2.5, 4)]
        let now = nine.addingTimeInterval(2.2 * 3600)
        #expect(MapLessonCard.pick(events, now: now, calendar: calendar) == .init(current: nil, next: events[1]))
        // A deadline is not a lesson; after the last, nothing.
        #expect(MapLessonCard.pick([lesson(4, 1, 1.5, kind: .deadline)], now: nine, calendar: calendar) == nil)
        #expect(MapLessonCard.pick(events, now: nine.addingTimeInterval(5 * 3600), calendar: calendar) == nil)
    }

    @Test func measuresHowMuchHasGone() {
        let end = nine.addingTimeInterval(7200)
        #expect(MapLessonCard.progress(start: nine, end: end, now: nine.addingTimeInterval(1800)) == 0.25)
        #expect(MapLessonCard.progress(start: nine, end: end, now: nine.addingTimeInterval(-60)) == 0)
        #expect(MapLessonCard.progress(start: nine, end: end, now: end.addingTimeInterval(60)) == 1)
        #expect(MapLessonCard.progress(start: nine, end: nine, now: nine) == 0)
    }

    @Test func saysWhenItEnds() {
        #expect(MapLessonCard.endsIn(from: nine, to: nine.addingTimeInterval(40 * 60)) == "termina tra 40 min")
        #expect(MapLessonCard.endsIn(from: nine, to: nine.addingTimeInterval(39 * 60 + 5)) == "termina tra 40 min")
        #expect(MapLessonCard.endsIn(from: nine, to: nine.addingTimeInterval(65 * 60)) == "termina tra 1 h 5 min")
        #expect(MapLessonCard.endsIn(from: nine, to: nine.addingTimeInterval(120 * 60)) == "termina tra 2 h")
        #expect(MapLessonCard.endsIn(from: nine, to: nine) == "termina tra 1 min")
    }

    @Test func walksFromTheLessonInProgressElseTheLastBefore() {
        let first = lesson(1, 0, 1), current = lesson(2, 1, 2), next = lesson(3, 2.5, 4)
        let events = [first, current, next]
        #expect(MapLessonCard.walkStart(to: next, in: events, now: nine.addingTimeInterval(1.5 * 3600)) == current)
        #expect(MapLessonCard.walkStart(to: next, in: events, now: nine.addingTimeInterval(2.2 * 3600)) == current)
        #expect(MapLessonCard.walkStart(to: current, in: events, now: nine.addingTimeInterval(0.95 * 3600)) == first)
        #expect(MapLessonCard.walkStart(to: first, in: events, now: nine) == nil)
    }
}
