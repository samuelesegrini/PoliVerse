import Foundation
import Testing
@testable import PoliVerse

@Suite("Lecture live activity")
struct LiveActivityTests {
    private func lecture(
        startingIn offset: TimeInterval, lasting: TimeInterval = 7200,
        kind: EventKind = .lecture
    ) -> AgendaEvent {
        let start = Date.now.addingTimeInterval(offset)
        return AgendaEvent(id: 1, title: "Analisi", start: start,
                           end: start.addingTimeInterval(lasting),
                           kind: kind, room: "3.0.1", roomAcronym: "3.0.1")
    }

    @Test("Phases follow the clock")
    func phases() {
        let event = lecture(startingIn: 3600)
        #expect(LiveActivityController.phase(of: event, at: .now) == .upcoming)
        #expect(LiveActivityController.phase(of: event, at: event.start) == .running)
        #expect(LiveActivityController.phase(
            of: event, at: event.start.addingTimeInterval(60)) == .running)
        #expect(LiveActivityController.phase(of: event, at: event.end) == .ended)
    }

    @Test("A lecture starting soon can be tracked")
    func startable() {
        #expect(LiveActivityController.canStart(lecture(startingIn: 1800)))
        #expect(LiveActivityController.canStart(lecture(startingIn: -600)))
    }

    @Test("A finished lecture cannot")
    func finished() {
        #expect(LiveActivityController.canStart(
            lecture(startingIn: -10_000, lasting: 3600)) == false)
    }

    @Test("A lecture days away cannot")
    func tooFarOff() {
        // Counting down for eleven hours is not a live activity, it is a
        // notification that never leaves.
        #expect(LiveActivityController.canStart(lecture(startingIn: 40_000)) == false)
    }

    @Test("Only lectures", arguments: [EventKind.exam, .deadline, .news, .custom])
    func onlyLectures(kind: EventKind) {
        #expect(LiveActivityController.canStart(
            lecture(startingIn: 1800, kind: kind)) == false)
    }

    @Test("The countdown deadline matches the phase")
    func deadlines() {
        let start = Date.now
        let end = start.addingTimeInterval(3600)
        let attributes = LectureActivityAttributes(
            title: "Analisi", room: "3.0.1", building: nil, start: start, end: end)
        #expect(attributes.deadline(for: .upcoming) == start)
        #expect(attributes.deadline(for: .running) == end)
        #expect(attributes.deadline(for: .ended) == end)
    }

    @Test("Location reads without repeating itself")
    func location() {
        func attributes(room: String?, building: String?) -> LectureActivityAttributes {
            LectureActivityAttributes(title: "x", room: room, building: building,
                                      start: .now, end: .now)
        }
        #expect(attributes(room: "3.0.1", building: "Edificio 3").location == "3.0.1 · Edificio 3")
        // The agenda repeats the room as the calendar name often enough that
        // "3.0.1 · 3.0.1" would be a common sight.
        #expect(attributes(room: "3.0.1", building: "3.0.1").location == "3.0.1")
        #expect(attributes(room: nil, building: "Edificio 3").location == "Edificio 3")
        #expect(attributes(room: nil, building: nil).location == nil)
    }
}
