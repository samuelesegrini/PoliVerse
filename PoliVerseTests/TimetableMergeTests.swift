import Foundation
import Testing
@testable import PoliVerse

/// Personal lessons shown in the agenda, until the official agenda has them.
@Suite("Timetable merge")
struct TimetableMergeTests {
    private let calendar = PoliMiDate.romeCalendar
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))! }
    private var week: DateInterval { DateInterval(start: monday, duration: 7 * 86400) }

    private func entry(_ code: String, _ title: String, slots: [(Int, Int)]) -> PersonalTimetable.Entry {
        PersonalTimetable.Entry(code: code, title: title, teacher: nil, semester: 1, lessonsStart: monday,
                                lessonsEnd: monday.addingTimeInterval(90 * 86400),
                                slots: slots.map { .init(weekday: $0.0, startMinutes: $0.1, endMinutes: $0.1 + 120,
                                                         room: "3.1.4", roomID: "46", address: "Edificio 3") })
    }

    private var timetable: PersonalTimetable {
        PersonalTimetable(name: "Rossi Mario", yearCode: "2026", entries: [
            entry("052496", "ALGORITHMS AND PARALLEL COMPUTING", slots: [(2, 495), (3, 615)]),
            entry("059156", "ANALISI MATEMATICA 1", slots: [(5, 615)]),
        ], builtAt: .now)
    }

    private func official(_ title: String, day: Int, minutes: Int, id: Int) -> AgendaEvent {
        let start = calendar.date(byAdding: .minute, value: minutes, to: calendar.date(byAdding: .day, value: day - 2, to: monday)!)!
        return AgendaEvent(id: id, title: title, start: start, end: start.addingTimeInterval(7200), kind: .lecture)
    }

    @Test("Personal lessons join the agenda, tagged and in order")
    func joins() {
        let merged = TimetableMerge.merge(official: [], timetable: timetable, in: week)
        #expect(merged.count == 3)
        #expect(merged.allSatisfy { $0.tags.contains(TimetableMerge.tag) && $0.id < 0 && $0.kind == .lecture })
        #expect(merged.map(\.start) == merged.map(\.start).sorted())
        #expect(merged.first?.room == "3.1.4")
    }

    @Test("Ids are stable, so a redraw does not treat lessons as new")
    func stableIDs() {
        #expect(TimetableMerge.merge(official: [], timetable: timetable, in: week).map(\.id)
            == TimetableMerge.merge(official: [], timetable: timetable, in: week).map(\.id))
    }

    @Test("A teaching the agenda confirms shows only the official lessons")
    func confirmedHidden() {
        let officialEvents = [official("Algorithms and parallel computing", day: 2, minutes: 495, id: 1),
                              official("Algorithms and parallel computing", day: 3, minutes: 615, id: 2)]
        let merged = TimetableMerge.merge(official: officialEvents, timetable: timetable, in: week)
        #expect(merged.filter { $0.tags.contains(TimetableMerge.tag) }.map(\.title) == ["ANALISI MATEMATICA 1"])
        #expect(merged.count == 3)
    }

    @Test("A retired timetable, or none, leaves the agenda untouched")
    func retired() {
        var copy = timetable
        copy.retiredAt = .now
        let officialEvents = [official("X", day: 2, minutes: 600, id: 1)]
        #expect(TimetableMerge.merge(official: officialEvents, timetable: copy, in: week) == officialEvents)
        #expect(TimetableMerge.merge(official: officialEvents, timetable: nil, in: week) == officialEvents)
    }

    @Test("Personal lessons are recognised when the cache is read back")
    func strip() {
        let merged = TimetableMerge.merge(official: [official("X", day: 2, minutes: 600, id: 1)], timetable: timetable, in: week)
        #expect(TimetableMerge.officialOnly(merged).map(\.id) == [1])
    }
}

@Suite("Official badge")
struct OfficialBadgeTests {
    private let lecture = AgendaEvent(id: 1, title: "X", start: .now, end: .now, kind: .lecture)

    @Test("Official lectures are marked only while a personal timetable is in use")
    func badge() {
        var timetable = PersonalTimetable(name: "A", yearCode: "2026", entries: [], builtAt: .now)
        #expect(TimetableMerge.marksOfficial(lecture, timetable: timetable))
        timetable.retiredAt = .now
        #expect(!TimetableMerge.marksOfficial(lecture, timetable: timetable))
        #expect(!TimetableMerge.marksOfficial(lecture, timetable: nil))
    }

    @Test("Personal lessons and non-lectures are never marked official")
    func notMarked() {
        let timetable = PersonalTimetable(name: "A", yearCode: "2026", entries: [], builtAt: .now)
        let personal = AgendaEvent(id: -1, title: "X", start: .now, end: .now, kind: .lecture, tags: [TimetableMerge.tag])
        let exam = AgendaEvent(id: 2, title: "X", start: .now, end: .now, kind: .exam)
        #expect(!TimetableMerge.marksOfficial(personal, timetable: timetable))
        #expect(!TimetableMerge.marksOfficial(exam, timetable: timetable))
    }
}
